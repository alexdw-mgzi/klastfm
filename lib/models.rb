class Artist < ActiveRecord::Base
  has_many :tracks
end

class Track < ActiveRecord::Base
  belongs_to :artist, :foreign_key => 'artist'
  belongs_to :statistic, :foreign_key => 'url', :primary_key => 'url'
end

class Statistic < ActiveRecord::Base
  has_one :track, :foreign_key => 'url', :primary_key => 'url'
  #has_one :artist, :through => :track, :foreign_key => 'url'
end

#class Url < ActiveRecord::Base
#end
