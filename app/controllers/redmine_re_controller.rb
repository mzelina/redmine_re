##
# super controller for the redmine RE plugin
# common methods used for (almost) all redmine_re controllers go here
class RedmineReController < ApplicationController
  menu_item :re

  NODE_CONTEXT_MENU_ICON = "bullet_toggle_plus.png"

  include ActionView::Helpers::AssetTagHelper
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper

  helper :watchers
  helper :application
  include WatchersHelper

  before_filter :load_settings, :authorize
  prepend_before_filter :first_load, :except => :configure
  prepend_before_filter :find_project

  def first_load
     @project_artifact = ReArtifactProperties.find_by_artifact_type_and_project_id("Project", @project.id)
     if @project_artifact.nil?
      @firstload = true
      redirect_to :controller => "re_settings", :action => "configure", :project_id => @project.id, :firstload => '1'    
    else
      @firstload = false
      unconfirmed = ReSetting.get_plain("unconfirmed", @project.id)
      
      if unconfirmed.nil? || unconfirmed == "true"
        flash[:notice] = t(:re_settings_have_to_save_again)
        redirect_to :controller => "re_settings", :action => "configure", :project_id => @project.id    
      end
    end 
  end

  def initialize_tree_data
    return if @firstload == true
    @project_artifact = ReArtifactProperties.find_by_project_id_and_artifact_type(@project.id, "Project")
    session[:expanded_nodes] << @project_artifact.id
    tree = []
    tree << create_tree(@project_artifact)
    @json_tree_data = tree.to_json
  end

  def load_settings
    # Check the settings cache for each request
    ReSetting.check_cache
    session[:expanded_nodes] ||= Set.new
    @re_artifact_order = ReSetting.get_serialized("artifact_order", @project.id)
    @re_relation_types = ReRelationtype.relation_types(@project.id, false)
    @re_used_relation_types = ReRelationtype.relation_types(@project.id, false, true)
    @re_artifact_settings = ReSetting.active_re_artifact_settings(@project.id)
    @re_relation_settings = ReSetting.active_re_relation_settings(@project.id)
  end

  def find_project
    # find the current project either by project name ( new action,..)
    if (params[:project_id])
      begin
        @project = Project.find(params[:project_id])
      rescue ActiveRecord::RecordNotFound
        render_404 :message => t(:re_404_invalid_project_id)
      end
      # or by artifact id (e.g. in edit actions or when called though ajax)
    elsif (params[:id])
      artifact = ReArtifactProperties.find(params[:id])
      @project = artifact.project unless artifact.nil?
    elsif (params[:re_artifact_properties])
      project_id = params[:re_artifact_properties][:project_id]
      @project = Project.find(project_id) unless project_id.blank?
    else
      render_404 :message => t(:re_404_artifact_not_found_or_project_missing)
    end
  end

  def new
    @artifact_type = self.controller_name # needed for ajax request
    logger.debug("############ CALLED NEW FOR ARTIFACT OF TYPE: " + @artifact_type)

    @artifact = @artifact_type.camelcase.constantize.new
    @artifact_properties = @artifact.re_artifact_properties

    if params[:parent_artifact_id]
      @parent = ReArtifactProperties.find(params[:parent_artifact_id])
    end

    if params[:sibling_id]
      @sibling = ReArtifactProperties.find(params[:sibling_id])
    end

    new_hook params

    render 're_artifact_properties/edit'
  end

  def create
    @artifact_type = self.controller_name
    logger.debug("############ Called edit for artifact of type: " + @artifact_type)

    @artifact = @artifact_type.camelcase.constantize.find_by_id(params[:id], :include => :re_artifact_properties) || @artifact_type.camelcase.constantize.new
    @artifact_properties = @artifact.re_artifact_properties
    
    @parent = nil

    @issues = @artifact_properties.issues

    #edit_hook_after_artifact_initialized params
    create_hook params

       @artifact.attributes = params[:artifact]
      # attributes that cannot be set by the user
      @artifact.project_id = @project.id
      @artifact.created_at = Time.now
      @artifact.updated_at = @artifact.created_at
      @artifact.updated_by = User.current.id
      @artifact.created_by = User.current.id if @artifact.new_record?

      # relation related attributes
      unless params[:sibling_id].blank?
        @sibling = ReArtifactProperties.find(params[:sibling_id])
        @parent = @sibling.parent
      end
      unless params[:parent_artifact_id].blank?
        @parent = ReArtifactProperties.find(params[:parent_artifact_id])
      end

      logger.debug("############ parent to set #{@parent.inspect}")
      unless @parent.nil?
        @artifact_properties.parent = @parent
      end

      valid = @artifact.valid?

      logger.debug("############ errors after validating #{@artifact_type} ##{@artifact.id}: #{@artifact.errors.inspect}")

      if valid && @artifact_properties.valid?
        flash.now[:notice] = t( @artifact_type + '_saved', :name => @artifact.name ) if @artifact.save
        edit_hook_valid_artifact_after_save params

        unless @sibling.nil?
          @artifact_properties.parent_relation.insert_at(@sibling.parent_relation.position + 1)
        end
        
        # Add Comment
        unless params[:comment].blank?
          comment = Comment.new
          comment.comments = params[:comment]
          comment.author = User.current
          @artifact_properties.comments << comment
          comment.save
        end

        # If sibling is not blank, then the option "create new artifact below" was called
        # and the artifact should beplaced below its sibling
        initialize_tree_data

      else
        edit_hook_invalid_artifact_cleanup params
      end

      unless params[:issue_id].blank?
        params[:issue_id].each do |iid|
          @artifact_properties.issues << Issue.find(iid)
        end
      end
    render :edit
  end

  def edit

    @artifact_type = self.controller_name
    logger.debug("############ Called edit for artifact of type: " + @artifact_type)

    @artifact = @artifact_type.camelcase.constantize.find_by_id(params[:id], :include => :re_artifact_properties) || @artifact_type.camelcase.constantize.new
    @artifact_properties = @artifact.re_artifact_properties

    @parent = nil

    @issues = @artifact_properties.issues

    edit_hook_after_artifact_initialized params

    # Remove Comment (Initiated via GET)
    if User.current.allowed_to?(:administrate_requirements, @project)
      unless params[:deletecomment_id].blank?
        comment = Comment.find_by_id(params[:deletecomment_id])
        comment.destroy unless comment.nil?
      end
    end

    render 're_artifact_properties/edit'  
  end

  def new_hook(paramsparams)
    logger.debug("#############: new_hook not called") 
  end

  def edit_hook_after_artifact_initialized(params)
    logger.debug("#############: edit_hook_after_artifact_initialized not called") 
  end

  def edit_hook_validate_before_save(params, artifact_valid)
    logger.debug("#############: edit_validate_before_save_hook not called") 
    return true
  end

  def edit_hook_valid_artifact_after_save(params)
    logger.debug("#############: edit_valid_artifact_after_save_hook not called") 
  end

  def edit_hook_invalid_artifact_cleanup(params)
    logger.debug("#############: edit_invalid_artifact_cleanup_hook not called") 
  end

  # filtering of re_artifacts. If request is post, filter was used already
  # and result should be displayed
  def enhanced_filter
    @project_id = params[:project_id]

    if request.post? # apply filter and show results
      source = params[:re_source_artifact][:data]
      source_searching = params[:re_source_artifact][:searching]
      sink = params[:re_sink_artifact][:data]
      sink_searching = params[:re_sink_artifact][:searching]
      source.delete_if { |key, value| value == "" }
      sink.delete_if { |key, value| value == "" }
        # search for artifacts matching the source_artifact_filter_criteria
      if params[:activated_searches].key?(:re_source_artifact)
        first_param = source.each.first
        @source_artifacts = find_first_artifacts_with_first_parameter(first_param, params[:re_source_artifact][:type])
        source.delete(first_param[0])
          # run through all given parameters and reduce the set of artifacts matching with each step
        for key in source.keys do
          @source_artifacts = reduce_search_result_with_parameter(@source_artifacts, key, source[key], source_searching[key])
        end
      end
        # search was only about artifacts, not about relationships
        # therefore just display artifacts without taking relationships into account
      render 'requirements/filter_results_simple'
      return
    end
    render 'requirements/enhanced_filter'
  end


    # This method takes a 2 value array with the name of the attribute to search for and its value;
    # it takes the hash with the searching forms like start with, greater_than and so on;
    # finally it takes the chosen artifact type to reduce the search.
    # The method evaluates the given parameter to find artifacts matching these first two
    # criteria (type and the first_param).
  def find_first_artifacts_with_first_parameter(filter_param, artifact_type)
    artifacts = []
    artifact_properties_attribute = false
    for column in ReArtifactProperties.content_columns do
      artifact_properties_attribute = true if column.name == filter_param[0]
    end

      # if attribute searched for belongs to RePropertiesAttributes, one can search for the artifact in ReArtifactProperties
    if artifact_properties_attribute # ReArtifactProperties.has_attribute?(filter_param[0])
      artifacts += ReArtifactProperties.find(:all, :conditions => [filter_param[0] + " LIKE ? AND artifact_type = ?", filter_param[1] + '%', artifact_type])
                                     # attribute is a special one used by one of the subclasses of ReArtifactProperties
    else
      case artifact_type
        when "ReSubtask", ""
          artifacts += ReSubtask.find(:all, :conditions => [filter_param[0] + " = ?", filter_param[1]])
        when "ReTask", ""
          artifacts += ReTask.find(:all, :conditions => [filter_param[0] + " = ?", filter_param[1]])
        when "ReGoal", ""
          artifacts += ReSubtask.find(:all, :conditions => [filter_param[0] + " = ?", filter_param[1]])
      end
    end
  end

  def reduce_search_result_with_parameter(source_artifacts, key, source_key, source_searching_key)
  end

  private

  def render_autocomplete_artifact_list_entry(artifact)
    # renders a list entry (<li> ... </li>) containing the artifacts name
    # and all its parent parents up to the project
    grandparents = []
    grandparent = artifact.parent
    unless grandparent.nil?
      while (grandparent.artifact_type != "Project")
        grandparents << grandparent
        grandparent = grandparent.parent
      end
    end

    li = '<li id="'
    li << artifact.id.to_s
    li << '">'

    for gp in grandparents.reverse
      li << gp.name + " &rarr; "
    end

    li << "<b>" + artifact.name + "</b>"
    li << '</li>'
    li
  end

  def create_tree(re_artifact_properties)
    # creates a hash containing re_artifact_properties and all its children
    # until a certain tree depth (BFS)
    # the result is a hash in the form
    # example format
    # 'data' : [
    # {
    # 'id' : 'node_2',
    # 'text' : 'Root node with options',
    # 'state' : { 'opened' : true, 'selected' : true },
    # 'children' : [ { 'text' : 'Child 1' }, .........]
    # }
    # ]
    #
    # to be rendered as json or xml. Used together with JStree right now 
    session[:expanded_nodes].delete(re_artifact_properties.id) if re_artifact_properties.children.empty?
    expanded = session[:expanded_nodes].include?(re_artifact_properties.id)

    artifact_type = re_artifact_properties.artifact_type.to_s.underscore
    artifact_name = re_artifact_properties.name.to_s
    artifact_id = re_artifact_properties.id.to_s
    has_children = !re_artifact_properties.children.empty?
    node = {}
    node['id'] = "node_" + artifact_id.to_s
    node['text'] = artifact_name
    node['type'] = artifact_type

    state = {}
    if expanded
      state['opened'] = true
    end
    node['state'] = state

    a_attr = {}
    a_attr['data-id'] = artifact_id.to_s
    unless artifact_type.eql?('project')
      a_attr['data-href'] = url_for(:controller => 're_artifact_properties', :action => 'show', :id => artifact_id)
      a_attr['data-delete-href'] = url_for(:controller => 're_artifact_properties', :action => 'destroy', :id => artifact_id)
    end
    node['a_attr'] = a_attr

    node_state = {}
    if has_children
      node_state ['opened'] = 'true' if expanded
    end

    node['state'] = node_state

    if has_children
      node['children'] = get_children(re_artifact_properties)
    end

    node
  end

  def get_children(re_artifact_properties)
    children = []
    
    for child in re_artifact_properties.children
      children << create_tree(child)
    end
    children
  end

  def filter
    if request.post?
      @filter = params[:filter]
      render 'requirements/filter_result'
    else
      @filter = ReQuery.new
      render 'requirements/filter'
    end
  end
end
