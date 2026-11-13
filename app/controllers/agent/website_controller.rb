module Agent
  class WebsiteController < BaseController
    content_security_policy only: :preview do |policy|
      policy.frame_ancestors :self
    end
    def show; end
    def update
      attributes = params.expect(agent_workspace: [ :name, :whatsapp, :presentation, :show_presentation, :show_catalog, :show_about, :about_text, :about_photo ])
      photo = attributes.delete(:about_photo)
      current_agent_workspace.assign_attributes(attributes)
      if photo.present?
        UploadValidator.call(photo, images_only: true)
        current_agent_workspace.about_photo = photo
      end
      current_agent_workspace.save!
      audit("agent_workspace.updated", current_agent_workspace)
      redirect_to agent_website_path, notice: "Tu página fue actualizada."
    rescue ActiveRecord::RecordInvalid
      render :show, status: :unprocessable_entity
    rescue UploadValidator::Invalid => error
      current_agent_workspace.errors.add(:about_photo, error.message)
      render :show, status: :unprocessable_entity
    end
    def about_photo
      photo = current_agent_workspace.about_photo
      raise ActiveRecord::RecordNotFound unless photo.attached?
      send_data photo.download, type: photo.content_type, disposition: "inline"
    end
    def preview
      @public_view = true
      return render "agent/public_catalog/index" unless current_agent_workspace.show_catalog?
      @catalog = PublicCatalogQuery.new(workspace: current_agent_workspace, filters: params.permit(*PublicCatalogQuery::FILTERS))
      @destinations = @catalog.destinations
      @trips, @pagination = paginate(@catalog.trips, per_page: 6)
      render "agent/public_catalog/index"
    end
  end
end
