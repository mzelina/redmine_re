require_dependency 'issue'

# Mixin for Issue Model
# Connects a Redmine Issue with an RE-Plugin Artifact
module IssuePatch
  def self.included(base)
    base.extend(ClassMethods)
    base.send(:include, InstanceMethods)

    #typing in class
    base.class_eval do

      #puts base.methods
      has_many :re_realizations, :dependent => :destroy
      has_many :re_artifact_properties, -> { distinct}, :through => :re_realizations
    end
  end

  module ClassMethods
    def tickets_with_end_overdue(project)
      #Tickets whose status should be set to closed by now!
      self.find(:all, :conditions=> ["due_date > ? AND status_id < 5 AND project_id= ?", Time.now, project.id] )
    end

    def tickets_with_start_overdue(project)
      self.find(:all, :conditions=> ["start_date < ? AND status_id < 2 AND project_id=?", Time.now, project.id])
    end
  end

  module InstanceMethods
    # Returns the number of artifacts assigned to a particular issue
    def re_artifacts_count
      re_artifact_properties.count
    end
  end
end

Issue.send(:include, IssuePatch)
