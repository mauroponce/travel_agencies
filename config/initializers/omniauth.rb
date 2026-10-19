OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.full_host = ENV.fetch("APP_URL", "http://localhost:3000")

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV.fetch("GOOGLE_CLIENT_ID", "development-client-id"),
    ENV.fetch("GOOGLE_CLIENT_SECRET", "development-client-secret"),
    scope: "openid email profile",
    prompt: "select_account",
    image_aspect_ratio: "square"
end
