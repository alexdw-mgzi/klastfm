class Lastfm
  include HTTParty
  base_uri 'ws.audioscrobbler.com/2.0'
#  debug_output $stderr

  def initialize(username, api_key)
    self.class.default_params :user => username, :api_key => api_key
  end

  def all_tracks
    options = {:method => 'library.gettracks', :page => 1}
    response = self.class.get('/', :query => options)
    begin
      total_pages = response['lfm']['tracks']['totalPages'].to_i
#     total_pages = 1
    rescue NoMethodError
      puts "ERROR: are you sure you edited the config/config.yaml and added your last.fm api key?"
      raise
    end

    tracks = []
    puts "getting ca. #{total_pages*50} tracks from last.fm"
    puts 'this will take some time...'
    bar = ProgressBar.new('getting data', total_pages)

    (1..total_pages).each do |page|
      tracks += self.tracks(page)
      # leave the pause since last.fm does not like too many request per second
      sleep 1
      bar.inc
    end
    bar.finish
    
    total_tracks = (tracks.size%50).zero? ? total_pages*50 : (total_pages-1)*50 + tracks.size%50
    [total_tracks, tracks]
  end

  def tracks(page)
    options = {:method => 'library.gettracks', :page => page}
    response = self.class.get('/', :query => options)
    tracks = []
    response['lfm']['tracks']['track'].each do |track|
      tracks << {
              :artist => track['artist']['name'],
              :title => track['name'],
              :playcount => track['playcount'].to_i
      }
    end
    tracks
  end
end
