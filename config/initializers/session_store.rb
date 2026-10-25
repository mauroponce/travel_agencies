secure_session = Rails.env.production? || Rails.env.staging?

Rails.application.config.session_store :cookie_store,
  key: "_turistack_session",
  secure: secure_session,
  httponly: true,
  same_site: :lax,
  domain: nil
