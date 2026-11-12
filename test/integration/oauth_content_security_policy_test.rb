require "test_helper"

class OauthContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "identity email conflict lookup redacts email from SQL logs" do
    user = create_user(email: "identity-private-unique@example.test")
    buffer = StringIO.new
    previous = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(buffer)
    identity = Auth::GoogleIdentity.call(OmniAuth::AuthHash.new(provider: "google_oauth2", uid: user.google_sub,
      info: { email: user.email, name: user.name }, extra: { id_info: { email_verified: true } }))
    assert_equal user, identity
    assert_not_includes buffer.string, user.email
  ensure
    ActiveRecord::Base.logger = previous if previous
  end

  test "Google form redirects allow only the pending authenticated return origin" do
    company = Company.create!(name: "Empresa CSP", slug: "csp-#{SecureRandom.hex(4)}")
    other = Company.create!(name: "Otra CSP", slug: "csp-other-#{SecureRandom.hex(4)}")
    host! company.platform_domain.hostname
    post auth_start_path
    continue_url = response.location
    host! PlatformHosts.auth_host
    get URI(continue_url).request_uri
    assert_response :success
    form_sources = response.headers.fetch("Content-Security-Policy").split(";").find { |directive| directive.strip.start_with?("form-action ") }.split
    assert_includes form_sources, PlatformHosts.url(host: company.platform_domain.hostname)
    assert_includes form_sources, PlatformHosts.url(host: PlatformHosts.auth_host)
    assert_includes form_sources, "https://accounts.google.com"
    assert_not_includes form_sources, PlatformHosts.url(host: other.platform_domain.hostname)
    assert_not_includes form_sources, "*"
    AuthenticationRequest.order(:created_at).last.update!(expires_at: 1.second.ago)
    get URI(continue_url).request_uri
    assert_response :unprocessable_entity
    assert_not_includes response.headers.fetch("Content-Security-Policy"), PlatformHosts.url(host: company.platform_domain.hostname)
  end
end
