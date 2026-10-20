class SessionsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context

  def create
    raise ActionController::RoutingError, "Not Found" unless Current.host_scope == "auth"
    user = Auth::GoogleIdentity.call(request.env.fetch("omniauth.auth"))
    user.update!(last_login_at: Time.current)
    authentication_request = nil
    membership = nil
    token = nil
    AuthenticationRequest.transaction do
      authentication_request = AuthenticationRequest.lock.find(session[:authentication_request_id])
      raise ActiveRecord::RecordNotFound unless authentication_request.available?
      raise ActiveRecord::RecordNotFound if authentication_request.company &&
        (authentication_request.company.status != "active" || !authentication_request.company_domain.active?)

      membership = membership_for(authentication_request, user)
      authorized = membership || (authentication_request.company.nil? && user.platform_operator?)
      _, token = AuthenticationCode.issue!(authentication_request:, user:, membership:) if authorized
      authentication_request.update!(used_at: Time.current)
    end
    return reject_authentication(authentication_request) unless token

    session.delete(:authentication_request_id)
    redirect_to PlatformHosts.url(host: authentication_request.return_hostname, path: auth_exchange_path,
      query: Rack::Utils.build_query(code: token)), allow_other_host: true
  rescue Auth::GoogleIdentity::InvalidIdentity => error
    reject_authentication(authentication_request, error.message)
  end

  def failure
    authentication_request = AuthenticationRequest.find_by(id: session.delete(:authentication_request_id))
    return head :unprocessable_entity unless authentication_request
    redirect_to PlatformHosts.url(host: authentication_request.return_hostname, path: "/",
      query: "auth_error=provider"), allow_other_host: true
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Sesión cerrada."
  end

  def test_sign_in
    raise ActionController::RoutingError, "Not Found" unless Rails.env.test?
    user = User.find_by!(email: params[:email])
    if Current.host_scope == "platform"
      raise Pundit::NotAuthorizedError unless user.platform_operator?
      reset_session
      session[:user_id] = user.id
      return redirect_to platform_companies_path
    end
    membership = user.memberships.active.find_by!(company: Current.company)
    role = params[:role].to_s
    raise Pundit::NotAuthorizedError unless membership.role?(role)
    reset_session
    session[:user_id] = user.id
    session[:role] = role
    redirect_to dashboard_path
  end

  private

  def membership_for(authentication_request, user)
    return if authentication_request.company.nil?

    CompanyInvitation.available.where(company: authentication_request.company)
      .where("lower(email) = ?", user.email.downcase).find_each { |invitation| invitation.accept!(user) }
    user.memberships.active.find_by(company: authentication_request.company)
  end

  def reject_authentication(authentication_request, message = nil)
    authentication_request&.update!(used_at: Time.current) if authentication_request&.used_at.nil?
    session.delete(:authentication_request_id)
    return head :unprocessable_entity unless authentication_request

    target = PlatformHosts.url(host: authentication_request.return_hostname, path: "/",
      query: Rack::Utils.build_query(auth_error: "unauthorized"))
    redirect_to target, allow_other_host: true, alert: message || "Tu cuenta no tiene acceso a este espacio."
  end
end
