class Lastfm
  include HTTParty
  base_uri 'ws.audioscrobbler.com/2.0'

  def initialize(username, api_key)
    self.class.default_params :user => username, :api_key => api_key
    #self.class.debug_output Logger.new('log/lastfm.log')
  end

  def week_list(pages=nil)
    response = self.class.get('/', :query => {:method => 'user.getweeklychartlist'})['lfm']['weeklychartlist']['chart']
    pages.nil? ? response : response[1..pages]
  rescue NoMethodError
    puts "ERROR: are you sure you edited the config/config.yaml and added your last.fm api key?"
    raise
  end
  
  def tracks_in_week(from, to)
    response = self.class.get('/', :query => {:method => 'user.getWeeklyTrackChart', :from => from, :to => to})
    response['lfm']['weeklytrackchart']['track']
  rescue NoMethodError
    puts "ERROR: are you sure you edited the config/config.yaml and added your last.fm api key?"
    raise
  end

  def all_tracks(pages=nil)
    if pages
      total_pages = pages
    else
      response = self.class.get('/', :query => {:method => 'library.gettracks', :page => 1})
      begin
        total_pages = response['lfm']['tracks']['totalPages'].to_i
      rescue NoMethodError
        puts "ERROR: are you sure you edited the config/config.yaml and added your last.fm api key?"
        raise
      end
    end

    tracks = {}
    puts "getting all tracks you ever submitted to last.fm (ca. #{total_pages*50})"
    bar = ProgressBar.new('get playcount', total_pages)

    (1..total_pages).each do |page|
      tracks = tracks.merge(self.tracks(page))
      # leave the pause since last.fm does not like too many request per second
      sleep 1
      bar.inc
    end
    bar.finish && puts
    tracks
  end

  def tracks(page)
    options = {:method => 'library.gettracks', :page => page}
    response = self.class.get('/', :query => options)
    tracks = {}
    lastfm = []
    response['lfm']['tracks']['track'].each_with_index do |track, i|
      lastfm << track
      artist = String.new(track['artist']['name'])
      title = String.new(track['name'])
      tracks['t'+Digest::MD5.hexdigest("#{artist}_#{title}".gsub(/\W/, '').upcase)] = {
              :artist => artist,
              :title => title,
              :playcount => track['playcount'].to_i,
              :index => (page-1)*50+i,
              :accessdate => 0,
              :createdate => 0,
              :score => 0
      }
    end
    File.open('data/lastfm_all_tracks.yaml', 'a') {|f| f.puts(lastfm.ya2yaml) }
    tracks
  end
end
