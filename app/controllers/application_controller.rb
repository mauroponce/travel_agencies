class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_authentication
  before_action :set_current_context
  helper_method :current_user, :current_company, :current_membership, :current_role

  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  private

  def current_user
    Current.user ||= User.find_by(id: session[:user_id])
  end

  def current_company = Current.company
  def current_membership = Current.membership
  def current_role = Current.role

  def require_authentication
    redirect_to root_path, alert: "Iniciá sesión con Google para continuar." unless current_user
  end

  def set_current_context
    Current.request_id = request.request_id
    Current.ip_address = request.remote_ip
    return unless current_user

    membership = current_user.memberships.active.includes(:company, :membership_roles).find_by(id: session[:membership_id])
    membership ||= current_user.memberships.active.includes(:company, :membership_roles).first
    return redirect_to(onboarding_path) unless membership

    role = session[:role].to_s
    role = membership.roles.first unless membership.role?(role)
    Current.membership = membership
    Current.company = membership.company
    Current.role = role
    session[:membership_id] = membership.id
    session[:role] = role
    Time.zone = Current.company.timezone
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
