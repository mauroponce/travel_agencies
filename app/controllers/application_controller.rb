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
  helper_method :current_user, :current_company, :current_membership, :current_role

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

  def resolve_request_host
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
    resolution = TenantResolver.call(request.host)
    Current.host_scope = resolution.scope.to_s
    Current.company = resolution.company
    Current.company_domain = resolution.company_domain
  end

  def enforce_host_scope
    allowed = case controller_path
    when "authentication"
      true
    when "sessions"
      action_name == "destroy" || (Current.host_scope == "auth" && %w[create failure].include?(action_name)) || Rails.env.test?
    when "landing", "onboardings"
      %w[tenant platform].include?(Current.host_scope)
    else
      platform_request? ? Current.host_scope == "platform" : Current.host_scope == "tenant"
    end
    raise ActionController::RoutingError, "Not Found" unless allowed
  end

  def require_authentication
    redirect_to root_path, alert: "Iniciá sesión con Google para continuar." unless current_user
  end

  def set_current_context
    return unless current_user

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

  def forbidden
    render file: Rails.public_path.join("403.html"), status: :forbidden, layout: false
  end

  def not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
