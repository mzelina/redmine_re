class ReRating < ActiveRecord::Base
  attr_accessible :value
  attr_accessible :re_artifact_properties_id

  belongs_to :re_artifact_properties
  belongs_to :user
end
