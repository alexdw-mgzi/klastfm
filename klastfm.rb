class Klastfm
  require 'rubygems'
  require 'yaml'
  require 'active_record'
  require 'httparty'
  require 'progressbar'

  require 'lib/models'
  require 'lib/lastfm'

  def initialize
    begin
      config = YAML.load_file("config/config.yaml")
    rescue Errno::ENOENT
      raise "config/config.yaml not found"
    end

    lastfm_user = config['lastfm_user']
    lastfm_api_key = config['lastfm_api_key']

    ActiveRecord::Base.establish_connection(
      :adapter  => 'mysql',
      :host     => config['host'],
      :database => config['database'],
      :username => config['username'],
      :password => config['password']
    )
    ActiveRecord::Base.logger = Logger.new(File.open('log/database.log', 'a'))

    all_entries, all_tracks = Lastfm.new(lastfm_user, lastfm_api_key).all_tracks
    div = all_entries/100.0
    tracks_not_found = []
    bar = ProgressBar.new('updating db', all_entries)

    all_tracks.each.with_index do |entry, i|
      tracks = Track.all(
              :conditions => ['UPPER(title) LIKE ? AND UPPER(name) LIKE ?', entry[:title].upcase, entry[:artist].upcase],
              :include => 'artist',
              :select => 'track.url'
      )

      unless tracks
        tracks_not_found << "#{entry[:artist]} - #{entry[:title]}"
        next
      end
      
      score = begin
        ((all_entries-i)/div)
      rescue ZeroDivisionError; 0; end

      tracks.each do |track|
        process_track(track, score, entry[:playcount])
        bar.inc
      end
    end
    bar.finish
    
    puts "tracks not found: #{tracks_not_found.join(', ')}" unless tracks_not_found.empty?
  end

  def process_track(track, score, playcount)
    if track.statistic.present?
      track.statistic.update_attributes(
              :playcount => playcount,
              :score => score
      )
    else
      time = Time.now.to_i
      track.create_statistic(
              :url => track.url,
              :createdate => time,
              :accessdate => time,
              :score => score,
              :rating => 0,
              :playcount => playcount
      )
    end
  end
end

Klastfm.new
