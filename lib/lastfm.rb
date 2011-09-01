class Lastfm
  include HTTParty
  base_uri 'ws.audioscrobbler.com/2.0'

  def initialize(username, api_key)
    self.class.default_params :user => username, :api_key => api_key
    #self.class.debug_output Logger.new('log/lastfm.log')
  end

  # just a random request to check if everything is ok
  def test_the_connection_to_lastfm
    get_with_retry({:method => 'library.gettracks', :page => 1})
  end

  def get_with_retry(query)
    retry_counter = 0
    begin
      self.class.get('/', :query => query)
    rescue Exception => e
      raise e if retry_counter > 10
      retry_counter += 1
      puts "#{retry_counter}. retry: ", e.inspect
      sleep 5
      retry
    end
  end

  def week_list(pages=nil)
    response =  get_with_retry({:method => 'user.getweeklychartlist'})['lfm']['weeklychartlist']['chart']
    pages.nil? ? response : response[1..pages]
  end
  
  def tracks_in_week(from, to)
    response = get_with_retry({:method => 'user.getWeeklyTrackChart', :from => from, :to => to})
    response['lfm']['weeklytrackchart']['track']
  end

  def all_tracks(pages=nil)
    if pages
      total_pages = pages
    else
      response = get_with_retry({:method => 'library.gettracks', :page => 1})
      total_pages = response['lfm']['tracks']['totalPages'].to_i
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
    begin
      response['lfm']['tracks']['track'].each_with_index do |track, i|
        begin
          url = Track.url_of(track['artist']['name'], track['name'])
          next unless url

          tracks[url] = {
                  :artist => track['artist']['name'].to_s,
                  :title => track['name'].to_s,
                  :playcount => track['playcount'].to_i,
                  :index => (page-1)*50+i,
                  :accessdate => 0,
                  :createdate => 0,
                  :score => 0
          }
        rescue
          puts "error with track", track
        end
      end
    rescue NoMethodError
      raise response.inspect
    end
    tracks
  end
end
