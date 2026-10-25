module Agent
  class WebsiteController < BaseController
    content_security_policy only: :preview do |policy|
      policy.frame_ancestors :self
    end
    def show; end
    def update
      current_agent_workspace.update!(params.expect(agent_workspace: [ :business_name, :public_name, :whatsapp, :presentation ]))
      audit("agent_workspace.updated", current_agent_workspace)
      redirect_to agent_website_path, notice: "Tu página fue actualizada."
    end
    def preview
      @suppliers = current_agent_workspace.agent_suppliers.active.order(:name, :id)
      @public_view = true
      @trips, @pagination = paginate(CatalogQuery.call(workspace: current_agent_workspace, filters: params.permit(*CatalogQuery::FILTERS), public_view: true))
      render "agent/public_catalog/index"
    end
  end
end
