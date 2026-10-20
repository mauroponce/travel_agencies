class PwaController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context

  def manifest
    response.headers["Cache-Control"] = "private, max-age=300"
    render formats: :json
  end

  def service_worker
    response.headers["Cache-Control"] = "no-cache"
    render formats: :js, content_type: "application/javascript"
  end
end
