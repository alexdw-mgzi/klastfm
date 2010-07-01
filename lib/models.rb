class Artist < ActiveRecord::Base
  has_many :tracks
end

class Track < ActiveRecord::Base
  belongs_to :artist, :foreign_key => 'artist', :primary_key => 'id'
  belongs_to :statistic, :foreign_key => 'url', :primary_key => 'url'
end

class Statistic < ActiveRecord::Base
  has_one :track
end
