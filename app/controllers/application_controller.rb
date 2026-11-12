class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :resolve_request_host
  before_action :enforce_host_scope
  before_action :require_authentication
  before_action :set_current_context
  helper_method :current_user, :current_company, :current_membership, :current_role, :current_agent_workspace

  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :not_found
  rescue_from TenantResolver::UnknownHost, TenantResolver::SuspendedCompany, with: :not_found

  private

  def current_user
    Current.user ||= User.find_by(id: session[:user_id])
  end

  def current_company = Current.company
  def current_membership = Current.membership
  def current_role = Current.role
  def current_agent_workspace = Current.agent_workspace

  def resolve_request_host
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
    resolution = TenantResolver.call(request.host, path: request.path)
    Current.host_scope = resolution.scope.to_s
    Current.company = resolution.company
    Current.company_domain = resolution.company_domain
    Current.agent_workspace = resolution.agent_workspace
    if Current.host_scope == "platform" && AgentWorkspace.enabled?
      if controller_path == "agent/public_catalog" && params[:agent_slug].present?
        Current.agent_workspace = AgentWorkspace.find_by!(slug: params[:agent_slug], status: "active")
        Current.host_scope = "agent"
      elsif controller_path.start_with?("agent/") && !%w[agent/onboarding agent/public_catalog].include?(controller_path)
        Current.agent_workspace = current_user&.agent_workspace
        Current.host_scope = "agent"
      elsif controller_path == "pwa" && current_user&.agent_workspace&.active?
        Current.agent_workspace = current_user.agent_workspace
        Current.host_scope = "agent"
      end
    end
  end

  def enforce_host_scope
    allowed = case controller_path
    when "authentication"
      true
    when "sessions"
      action_name == "destroy" || (Current.host_scope == "auth" && %w[create failure].include?(action_name)) || Rails.env.test?
    when "agent/onboarding"
      AgentWorkspace.enabled? && AgentWorkspace.self_signup_enabled? && Current.host_scope == "platform"
    when "landing", "onboardings"
      %w[tenant platform agent].include?(Current.host_scope)
    when "contexts"
      %w[tenant platform agent].include?(Current.host_scope)
    when "pwa"
      %w[tenant agent].include?(Current.host_scope)
    else
      if controller_path.start_with?("agent/")
        Current.host_scope == "agent"
      else
        platform_request? ? Current.host_scope == "platform" : Current.host_scope == "tenant"
      end
    end
    raise ActionController::RoutingError, "Not Found" unless allowed
  end

  def require_authentication
    redirect_to root_path, alert: "Iniciá sesión con Google para continuar." unless current_user
  end

  def set_current_context
    return unless current_user

    if Current.host_scope == "agent"
      raise Pundit::NotAuthorizedError unless current_agent_workspace&.active? && current_agent_workspace.owner_id == current_user.id
      Current.role = "agent"
      Time.zone = current_agent_workspace.timezone
      return
    end

    if platform_request? && current_user.platform_operator?
      Current.role = "operator"
      return
    end

    membership = current_user.memberships.active.includes(:company, :membership_roles).find_by(company: current_company)
    return redirect_to(root_path, alert: "Tu cuenta no tiene acceso a esta agencia.") unless membership

    role = session[:role].to_s
    role = membership.membership_roles.order(:created_at, :id).pick(:role) unless membership.role?(role)
    Current.membership = membership
    Current.role = role
    session[:role] = role
    Time.zone = Current.company.timezone
  end

  def platform_request?
    controller_path.start_with?("platform/")
  end

  def require_role!(*roles)
    raise Pundit::NotAuthorizedError unless roles.map(&:to_s).include?(current_role)
  end

  def paginate(scope, param: :page, per_page: Pagination::DEFAULT_PER_PAGE)
    Pagination.call(scope, page: params[param], per_page:)
  end

  def forbidden
    render file: Rails.public_path.join("403.html"), status: :forbidden, layout: false
  end

  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
