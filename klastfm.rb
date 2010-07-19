#!/usr/bin/env ruby

# encoding: UTF-8
$KCODE = 'UTF8' unless RUBY_VERSION >= '1.9'

class Klastfm
  require 'rubygems'
  require 'yaml'
  require 'active_record'
  require 'httparty'
  require 'progressbar'
  require 'ya2yaml'

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

    # anyone knows how to test the db-connection?
    begin
      Track.first
    rescue Mysql::Error
      puts 'Cannot connect to the database. Check config/config.yaml'
      raise
    end

    @lastfm = Lastfm.new(config['lastfm']['user'], config['lastfm']['api_key'])
    @load_all_tracks_from_yaml = ARGV.first.present?

    @all_tracks = nil
    @pages = nil
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

  def get_all_tracks
    if @load_all_tracks_from_yaml
      raise 'data/all_tracks.yaml does not exist' unless File.exists?('data/all_tracks.yaml')
      puts 'loading all tracks from yaml'
      @all_tracks = YAML.load_file('data/all_tracks.yaml')
    else
      Dir.glob('data/*.yaml').map{|f| File.delete(f)}
      @all_tracks = @lastfm.all_tracks(@pages)
    end
  end

  def score_tracks
    @all_tracks.each do |_,track|
      next if track.nil?
      score = begin
        ((@all_tracks.size-track[:index])/(@all_tracks.size/100.0))
      rescue ZeroDivisionError; 0; end
      track[:score] = score<0 ? 0 : score
    end
  end

  def date_tracks
    # reset the dates for all tracks
    Statistic.update_all('createdate = 0, accessdate = 0')

    week_list = @lastfm.week_list(@pages)
    puts "getting all tracks played in the last #{week_list.size} weeks"
    bar = ProgressBar.new('date tracks', week_list.size)
    tracks_not_found = []
    week_list.each do |week|
      bar.inc
      @lastfm.tracks_in_week(week['from'], week['to']).each do |track|
        md5 = 't'+Digest::MD5.hexdigest("#{track['artist']}_#{track['name']}".gsub(/\W/, '').upcase)
        if @all_tracks[md5].nil?
          tracks_not_found << "#{track['name']} - #{track['artist']}"
          next
        end
        if week['from'].to_i < @all_tracks[md5][:createdate] || @all_tracks[md5][:createdate].zero?
          @all_tracks[md5][:createdate] = week['from'].to_i
        end
        if week['to'].to_i > @all_tracks[md5][:accessdate]
          @all_tracks[md5][:accessdate] = week['to'].to_i
        end
      end
    end
    File.open('data/all_tracks_not_found_in_your_collection.yaml', 'w') {|f| f.write( tracks_not_found.ya2yaml ) }
    File.open('data/all_tracks.yaml', 'w') {|f| f.write( @all_tracks.ya2yaml ) }
    bar.finish && puts
  end

  def save
    puts "save the statistics of all #{@all_tracks.size} tracks to database"
    bar = ProgressBar.new('saving', @all_tracks.size)
    @all_tracks.each do |_,track|
      bar.inc

      artist = Artist.first(:conditions => ['name SOUNDS LIKE ?', track[:artist]])
      next unless artist.present?
      
      Statistic.all(
              :conditions => ['artist = ? AND tracks.title SOUNDS LIKE ?', artist.id, track[:title]],
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
    puts "all done"
  end
end

t=Time.now
klastfm = Klastfm.new
klastfm.create_statistics
klastfm.get_all_tracks
klastfm.score_tracks
klastfm.date_tracks
klastfm.save
puts "Runtime: #{((Time.now-t)/60).to_i} minutes"
