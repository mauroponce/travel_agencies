require "test_helper"
require "open3"

class ProtectedEnvironmentBootTest < ActiveSupport::TestCase
  test "staging boots with forced SSL and secure host-only cookies" do
    env = {
      "RAILS_ENV" => "staging",
      "SECRET_KEY_BASE" => "a" * 64,
      "ACTIVE_RECORD_ENCRYPTION_KEY" => "b" * 64,
      "DB_HOST" => "localhost",
      "DB_USER" => "turistack",
      "DB_PASSWORD" => "secret",
      "DB_NAME" => "turistack_staging",
      "REDIS_URL" => "redis://localhost:6379/15",
      "PLATFORM_BASE_DOMAIN" => "staging.example.com",
      "PLATFORM_HOST" => "staging.example.com",
      "AUTH_HOST" => "auth.staging.example.com",
      "CUSTOM_DOMAIN_CNAME_TARGET" => "tenants.staging.example.com",
      "CADDY_SITE_ADDRESSES" => "staging.example.com, auth.staging.example.com",
      "GOOGLE_CLIENT_ID" => "client-id",
      "GOOGLE_CLIENT_SECRET" => "client-secret",
      "SMTP_HOST" => "smtp.example.com",
      "APP_PROTOCOL" => "https"
    }
    script = <<~'RUBY'
      options = Rails.application.config.session_options
      print [Rails.application.config.force_ssl, Rails.application.config.assume_ssl,
        options[:secure], options[:httponly], options[:same_site], options[:domain].inspect].join("|")
      STDOUT.flush
      exit! 0
    RUBY

    output, error, status = Open3.capture3(env, "bin/rails", "runner", script, chdir: Rails.root.to_s)

    assert status.success?, error
    assert_equal "true|true|true|true|lax|nil", output
  end
end
