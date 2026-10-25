class PwaController < ApplicationController
  skip_forgery_protection only: :service_worker
  skip_before_action :require_authentication
  skip_before_action :set_current_context
  before_action do
    @pwa_id = Current.agent_workspace ? "agent-#{Current.agent_workspace.id}" : Current.company.id
    @pwa_name = Current.agent_workspace&.business_name || Current.company.name
  end

  def manifest
    response.headers["Cache-Control"] = "private, max-age=300"
    render formats: :json
  end

  def service_worker
    response.headers["Cache-Control"] = "no-cache"
    render formats: :js, content_type: "application/javascript"
  end
end
