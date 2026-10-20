class AuthenticationController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context

  def start
    raise ActionController::RoutingError, "Not Found" unless %w[tenant platform].include?(Current.host_scope)

    if Current.host_scope == "platform" && current_user&.platform_operator?
      return redirect_to platform_companies_path
    end

    nonce = SecureRandom.urlsafe_base64(32)
    session[:authentication_browser_nonce] = nonce
    authentication_request, token = AuthenticationRequest.issue!(company: Current.company,
      company_domain: Current.company_domain, return_hostname: request.host, browser_nonce: nonce)
    redirect_to PlatformHosts.url(host: PlatformHosts.auth_host, path: auth_continue_path,
      query: Rack::Utils.build_query(request_token: token)), allow_other_host: true
  end

  def continue
    require_auth_host!
    authentication_request = AuthenticationRequest.find_available(params[:request_token])
    return render plain: "La solicitud de acceso venció. Volvé a la agencia e intentá nuevamente.", status: :unprocessable_entity unless authentication_request

    session[:authentication_request_id] = authentication_request.id
    render :continue
  end

  def exchange
    raise ActionController::RoutingError, "Not Found" unless %w[tenant platform].include?(Current.host_scope)

    code = AuthenticationCode.find_by_token(params[:code])
    raise ActiveRecord::RecordNotFound unless code
    nonce = session[:authentication_browser_nonce].to_s
    authenticated_user = nil
    membership = nil
    code.with_lock do
      raise ActiveRecord::RecordNotFound unless code.available?
      raise ActiveRecord::RecordNotFound unless code.target_hostname == PlatformHosts.normalize(request.host)
      raise ActiveRecord::RecordNotFound unless nonce.present? &&
        ActiveSupport::SecurityUtils.secure_compare(code.browser_nonce_digest, AuthenticationCode.digest(nonce))

      if code.company
        raise ActiveRecord::RecordNotFound unless Current.company&.id == code.company_id
        membership = code.membership
        raise Pundit::NotAuthorizedError unless membership&.reload&.active? && membership.user_id == code.user_id
      else
        raise Pundit::NotAuthorizedError unless Current.host_scope == "platform" && code.user.platform_operator?
      end
      authenticated_user = code.user
      code.update!(consumed_at: Time.current)
    end

    reset_session
    session[:user_id] = authenticated_user.id
    if membership
      session[:role] = membership.membership_roles.order(:created_at, :id).pick(:role)
      redirect_to dashboard_path, notice: "Bienvenido."
    else
      redirect_to platform_companies_path, notice: "Bienvenido."
    end
  end

  private

  def require_auth_host!
    raise ActionController::RoutingError, "Not Found" unless Current.host_scope == "auth"
  end
end
