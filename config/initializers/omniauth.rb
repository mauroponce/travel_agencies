OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true
require Rails.root.join("lib/oauth_host_guard")
oauth_protocol = ENV.fetch("APP_PROTOCOL", Rails.env.production? ? "https" : "http")
oauth_base_domain = ENV.fetch("PLATFORM_BASE_DOMAIN", Rails.env.test? ? "example.test" : "lvh.me")
oauth_host = ENV.fetch("AUTH_HOST", "auth.#{oauth_base_domain}")
oauth_port = ENV["APP_PORT"].presence
OmniAuth.config.full_host = "#{oauth_protocol}://#{oauth_host}#{":#{oauth_port}" if oauth_port}"

Rails.application.config.middleware.use OauthHostGuard

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV.fetch("GOOGLE_CLIENT_ID", "development-client-id"),
    ENV.fetch("GOOGLE_CLIENT_SECRET", "development-client-secret"),
    scope: "openid email profile",
    prompt: "select_account",
    image_aspect_ratio: "square"
end
