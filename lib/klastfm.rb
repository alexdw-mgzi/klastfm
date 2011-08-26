class Klastfm
  require 'rubygems'
  require 'yaml'
  require 'active_record'
  require 'logger'
  require 'httparty'
  require 'progressbar'

  require 'lib/models'
  require 'lib/lastfm'

  def initialize
    begin
      config = YAML.load_file('config/config.yaml')
    rescue Errno::ENOENT
      raise 'config/config.yaml not found'
    end

    Dir.mkdir('log') unless File.exists?('log')
    Dir.mkdir('data') unless File.exists?('data')
    ActiveRecord::Base.establish_connection(config['mysql'].merge({:adapter => 'mysql', :encoding => 'utf8'}))
    ActiveRecord::Base.logger = Logger.new('log/database.log')

    # just a random request to check if everything is ok
    # anyone knows how to test the db-connection?
    begin
      Track.first
    rescue Mysql::Error
      raise 'Cannot connect to the database. Check config/config.yaml'
    end

    @lastfm = Lastfm.new(config['lastfm']['user'], config['lastfm']['api_key'])
    @set_dates = config['lastfm']['set_dates']

    begin
      @lastfm.test_the_connection_to_lastfm
    rescue
      raise "ERROR: Connection to last.fm failed. Are you sure you added your last.fm api key to config/config.yaml?"
    end

    @all_tracks = nil
    @pages = nil
  end

  def get_all_tracks
    @all_tracks = @lastfm.all_tracks(@pages)
  end

  def create_statistics
    tracks = Track.all(:select => 'url', :order => 'url')
    puts 'creating a statistic entry for every track'
    bar = ProgressBar.new('creating statistics', tracks.size)
    tracks.each do |track|
      Statistic.find_or_create_by_url(track.url, {
              :url => track.url,
              :createdate => 0,
              :accessdate => 0,
              :score => 0,
              :rating => 0,
              :playcount => 0
      })
      bar.inc
    end
    bar.finish && puts
  end

  def score_tracks
    @all_tracks.each do |_,track|
      next if track.nil?
      score = begin
        ((@all_tracks.size-track[:index])/(@all_tracks.size/100.0))
      rescue ZeroDivisionError; 0 end
      track[:score] = score<0 ? 0 : score
    end
  end

  def date_tracks
    return unless @set_dates
    Statistic.update_all('createdate = 0, accessdate = 0', ['url in (?)', @all_tracks.keys])

    week_list = @lastfm.week_list(@pages)
    puts "getting all tracks played in the last #{week_list.size} weeks"
    bar = ProgressBar.new('date tracks', week_list.size)
    tracks_not_found = []
    week_list.each do |week|
      bar.inc
      @lastfm.tracks_in_week(week['from'], week['to']).each do |track|
        url = Track.url_of(track['name'], track['artist'])
        if url.nil? || @all_tracks[url].nil?
          tracks_not_found << "#{track['artist']} - #{track['name']}"
          next
        end
        if week['from'].to_i < @all_tracks[url][:createdate] || @all_tracks[url][:createdate].zero?
          @all_tracks[url][:createdate] = week['from'].to_i
        end
        if week['to'].to_i > @all_tracks[url][:accessdate]
          @all_tracks[url][:accessdate] = week['to'].to_i
        end
      end
    end
    File.open('data/all_tracks_not_found_in_your_collection.yaml', 'w') {|f| f.write( tracks_not_found.sort.to_yaml ) }
    bar.finish && puts
  end

  def save_statistic!
    puts "save the statistics of all #{@all_tracks.size} tracks to database"
    bar = ProgressBar.new('saving', @all_tracks.size)
    @all_tracks.each do |_,track|
      bar.inc
      artist = Artist.first(:conditions => ['name = ?', track[:artist]])
      next unless artist.present?

      Statistic.all(
              :conditions => ['artist = ? AND tracks.title = ?', artist.id, track[:title]],
              :include => 'track'
      ).each do |statistic|
        statistic.update_attributes(
                :playcount => track[:playcount],
                :score => track[:score],
                :accessdate => track[:accessdate],
                :createdate => track[:createdate]
        )
      end
    end
    bar.finish && puts
  end
end
