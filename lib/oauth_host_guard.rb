class OauthHostGuard
  OAUTH_PATH = %r{\A/auth/(?:google_oauth2(?:/callback)?|failure)\z}

  def initialize(app)
    @app = app
  end

  def call(env)
    request = ActionDispatch::Request.new(env)
    if request.path.match?(OAUTH_PATH) && PlatformHosts.normalize(request.host) != PlatformHosts.auth_host
      return [ 404, { "Content-Type" => "text/plain", "Cache-Control" => "no-store" }, [ "Not Found" ] ]
    end
    @app.call(env)
  end
end
