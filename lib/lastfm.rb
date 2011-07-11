class Lastfm
  include HTTParty
  base_uri 'ws.audioscrobbler.com/2.0'

  def initialize(username, api_key, tag_greater_than)
    self.class.default_params :user => username, :api_key => api_key
    @tag_greater_than = tag_greater_than.to_i
    #self.class.debug_output Logger.new('log/lastfm.log')
  end

  def get_with_retry(query)
    retry_counter = 0
    begin
      self.class.get('/', :query => query)
    rescue NoMethodError => e
      raise e if retry_counter > 3
      retry_counter += 1
      sleep 5
      retry
    end
  end

  def week_list(pages=nil)
    response =  get_with_retry({:method => 'user.getweeklychartlist'})['lfm']['weeklychartlist']['chart']
    pages.nil? ? response : response[1..pages]
  rescue NoMethodError
    puts "ERROR: are you sure you edited the config/config.yaml and added your last.fm api key?"
    raise
  end
  
  def tracks_in_week(from, to)
    response = get_with_retry({:method => 'user.getWeeklyTrackChart', :from => from, :to => to})
    response['lfm']['weeklytrackchart']['track']
  rescue NoMethodError
    puts "ERROR: are you sure you edited the config/config.yaml and added your last.fm api key?"
    raise
  end

  def all_tracks(pages=nil)
    if pages
      total_pages = pages
    else
      response = get_with_retry({:method => 'library.gettracks', :page => 1})
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
    response = get_with_retry({:method => 'library.gettracks', :page => page})
    tracks = {}
    lastfm = []
    response['lfm']['tracks']['track'].each_with_index do |track, i|
      begin
        lastfm << track

        artist = track['artist']['name'].to_s
        title = track['name'].to_s
        url = Track.url_of(artist, title)
        next unless url

        tracks[url] = {
                :artist => artist,
                :title => title,
                :playcount => track['playcount'].to_i,
                :index => (page-1)*50+i,
                :accessdate => 0,
                :createdate => 0,
                :score => 0
        }
      rescue; end
    end
#    File.open('data/lastfm_all_tracks.yaml', 'a') {|f| f.puts(lastfm.ya2yaml) }
    tracks
  end

  def tags(artist, track)
    tags = []
    return tags if artist.blank? || track.blank?
    response = get_with_retry({:method => 'track.gettoptags', :artist => artist, :track => track})
    response['lfm']['toptags']['tag'].each do |tag|
      tags << tag['name'] if tag['count'].to_i > @tag_greater_than
    end rescue nil
    tags
  end
end
