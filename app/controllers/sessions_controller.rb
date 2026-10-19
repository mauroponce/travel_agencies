class SessionsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context

  def create
    user = Auth::GoogleIdentity.call(request.env.fetch("omniauth.auth"))
    reset_session
    session[:user_id] = user.id
    user.update!(last_login_at: Time.current)
    CompanyInvitation.available.where("lower(email) = ?", user.email.downcase).find_each { |invitation| invitation.accept!(user) }
    DemoProvisioner.call(user) if ENV["DEMO_GOOGLE_EMAIL"].to_s.casecmp?(user.email)

    redirect_to(user.memberships.active.exists? ? dashboard_path : onboarding_path, notice: "Bienvenido a NexoViajes.")
  rescue Auth::GoogleIdentity::InvalidIdentity => error
    redirect_to root_path, alert: error.message
  end

  def failure
    redirect_to root_path, alert: "No pudimos validar tu cuenta de Google."
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Sesión cerrada."
  end

  def test_sign_in
    raise ActionController::RoutingError, "Not Found" unless Rails.env.test?
    user = User.find_by!(email: params[:email])
    membership = user.memberships.active.joins(:company).find_by!(companies: { slug: params[:company] })
    role = params[:role].to_s
    raise Pundit::NotAuthorizedError unless membership.role?(role)
    reset_session
    session[:user_id] = user.id
    session[:membership_id] = membership.id
    session[:role] = role
    redirect_to dashboard_path
  end
end
