class Artist < ActiveRecord::Base
  self.primary_key = 'id'
  has_many :tracks, :foreign_key => 'artist'
end

class Track < ActiveRecord::Base
  self.primary_key = 'id'
  belongs_to :artist, :foreign_key => 'artist'
  belongs_to :statistic, :foreign_key => 'url', :primary_key => 'url'
  has_many :taggings, :foreign_key => 'url', :primary_key => 'url'

  def self.url_of(artist, title)
    t = first(
            :select => 'tracks.url',
            :conditions => [ "artists.name = ? AND title = ?", artist, title ],
            :joins => :artist
    )
    t.nil? ? nil : t.url
  end
end

class Statistic < ActiveRecord::Base
  self.primary_key = 'id'
  has_one :track, :foreign_key => 'url', :primary_key => 'url'
end
