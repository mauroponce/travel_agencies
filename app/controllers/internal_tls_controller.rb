class InternalTlsController < ActionController::Base
  # No browser session or tenant resolution: Caddy calls this on the private Docker network.
  def show
    secret = ENV["CADDY_ASK_SECRET"].to_s
    valid = secret.present? && ActiveSupport::SecurityUtils.secure_compare(secret, params[:token].to_s)
    return head :forbidden unless valid && AgentWorkspace.enabled?
    hostname = PlatformHosts.normalize(params[:domain])
    registration = HostnameRegistration.includes(:agent_workspace).find_by(hostname:)
    allowed = registration&.agent_workspace&.active? && hostname == registration.agent_workspace.hostname &&
      hostname.end_with?(".#{PlatformHosts.base_domain}") && !PlatformHosts.reserved_subdomain?(registration.agent_workspace.subdomain)
    head(allowed ? :no_content : :forbidden)
  end
end
