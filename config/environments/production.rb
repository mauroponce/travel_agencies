require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym
  config.active_storage.variant_processor = :disabled

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = ENV["FORCE_SSL"] == "true"

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = ENV["FORCE_SSL"] == "true"

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL") }

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :sidekiq

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  platform_base_domain = ENV.fetch("PLATFORM_BASE_DOMAIN")
  platform_host = ENV.fetch("PLATFORM_HOST", "platform.#{platform_base_domain}")
  auth_host = ENV.fetch("AUTH_HOST", "auth.#{platform_base_domain}")
  config.action_mailer.default_url_options = { host: platform_host, protocol: ENV.fetch("APP_PROTOCOL", "https") }
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("SMTP_HOST"), port: ENV.fetch("SMTP_PORT", 587).to_i,
    user_name: ENV["SMTP_USERNAME"], password: ENV["SMTP_PASSWORD"],
    authentication: ENV.fetch("SMTP_AUTH", "plain"), enable_starttls_auto: true
  }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  config.hosts = [
    platform_host,
    auth_host,
    /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.#{Regexp.escape(platform_base_domain)}\z/,
    lambda do |host|
      CompanyDomain.where(status: "active").exists?(hostname: host.to_s.downcase.delete_suffix("."))
    rescue ActiveRecord::StatementInvalid
      false
    end
  ]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
