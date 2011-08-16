class RequirementsController < RedmineReController
  unloadable
  menu_item :re

  def index
    @project_artifact = ReArtifactProperties.find_by_artifact_type_and_project_id("Project", @project.id)
    
    if @project_artifact.nil? || @re_artifact_order.nil? || @re_relation_order.nil?
      redirect_to :controller => "re_settings", :action => "configure", :project_id => @project.id, :firstload => '1'
    end
  end
  
  def delegate_tree_drop
    # The following method is called via if somebody drops an artifact on the tree.
    # It transmits the drops done in the tree to the database in order to last
    # longer than the next refresh of the browser.
    new_parent_id = params[:new_parent_id]
    sibling_id = params[:ancestor_id] # WRONG NOMENCLATUR! ancestor_id => sibling_id
    moved_artifact_id = params[:id]
    insert_postition = params[:position]

    moved_artifact = ReArtifactProperties.find(moved_artifact_id)
    
		new_parent = nil
		begin
	 	  new_parent = ReArtifactProperties.find(new_parent_id) if not new_parent_id.empty?
		rescue ActiveRecord::RecordNotFound
      new_parent = ReArtifactProperties.find_by_project_id_and_artifact_type(moved_artifact.project_id, "Project")
		end
    session[:expanded_nodes] << new_parent.id
		
		sibling = nil
    sibling = ReArtifactProperties.find(sibling_id) if not sibling_id.empty?

    position = 1
    
    case insert_postition
    when 'before'
      position = (sibling.position - 1) unless sibling.nil? || sibling.position.nil?
    when 'after'
      position = (sibling.position + 1) unless sibling.nil? || sibling.position.nil?
    else
      position = 1
    end
      
    
    moved_artifact.set_parent(new_parent, position)
   
    result = {}
    result['status'] = 1
    result['insert_pos'] = position.to_s
    result['sibling'] = sibling.position.to_s + ' ' + sibling.name.to_s unless sibling.nil? || sibling.position.nil?
    
    render :json => result
  end

  # first tries to enable a contextmenu in artifact tree
  def context_menu
    @artifact =  ReArtifactProperties.find_by_id(params[:id])

    render :text => "Could not find artifact.", :status => 500 unless @artifact

    @subartifact_controller = @artifact.artifact_type.to_s.underscore
    @back = params[:back_url] || request.env['HTTP_REFERER']

    render :layout => false
  end

  def treestate
    # this method saves the state of a node
    # i.e. when you open or close a node in the tree
    # this state will be saved in the session
    # whenever you render the tree the rendering function will ask the
    # session for the nodes that are "opened" to render the children
    node_id = params[:id].to_i
    ret = ''
    case params[:open]
      when 'data'
        ret = nil
        if node_id.eql? -1
          re_artifact_properties = ReArtifactProperties.find_by_project_id_and_artifact_type(@project.id, "Project")
          ret = create_tree(re_artifact_properties, 1)
        else
          session[:expanded_nodes] << node_id
          re_artifact_properties =  ReArtifactProperties.find(node_id)
          ret = render_json_tree(re_artifact_properties, 1)
        end
        render :json => ret
      when 'true'
        session[:expanded_nodes] << node_id
        render :text => "node #{node_id} opened"
      else
        session[:expanded_nodes].delete(node_id)
        render :text => "node #{node_id} closed"
    end
  end

#######
private
#######

end