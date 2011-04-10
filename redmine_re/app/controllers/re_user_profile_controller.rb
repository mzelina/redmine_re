class ReUserProfileController < RedmineReController
  unloadable

  def new
    # redirects to edit to be more dry

    redirect_to :action => 'edit', :project_id => params[:project_id]
  end

  def edit
    @re_user_profile = ReUserProfile.find_by_id(params[:id], :include => :re_artifact_properties) || ReUserProfile.new
    
    # render html for tree
    @html_tree = create_tree
    
    if request.post?
      @re_user_profile.attributes = params[:re_user_profile]
      add_hidden_re_artifact_properties_attributes @re_user_profile

      flash[:notice] = t(:re_user_profile_saved) if save_ok = @re_user_profile.save

      if save_ok && ! params[:parent_artifact_id].empty?
        @parent = ReArtifactProperties.find(params[:parent_artifact_id])
        @re_user_profile.set_parent(@parent, 1)
      end
      
      redirect_to :action => 'edit', :id => @re_user_profile.id and return if save_ok
    end
  end

end