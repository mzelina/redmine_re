class ReRating < ActiveRecord::Base
  attr_accessible :value

  belongs_to :re_artifact_properties
  belongs_to :user
end
