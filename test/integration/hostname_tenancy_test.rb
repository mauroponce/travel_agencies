require "test_helper"

class HostnameTenancyTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Multi Agencia")
    @company_a = Company.create!(name: "Agencia A", slug: "agencia-a-#{SecureRandom.hex(3)}")
    @company_b = Company.create!(name: "Agencia B", slug: "agencia-b-#{SecureRandom.hex(3)}")
    @membership_a = create_membership(company: @company_a, user: @user, roles: %w[admin])
    @membership_b = create_membership(company: @company_b, user: @user, roles: %w[reseller])
    @trip_a = create_trip(company: @company_a, slug: "viaje-a")
    @trip_b = create_trip(company: @company_b, slug: "viaje-b")
  end

  test "unknown and suspended hostnames are rejected" do
    host! "unknown.example.test"
    get root_path
    assert_response :not_found

    @company_a.update!(status: "suspended")
    host! @company_a.platform_domain.hostname
    get root_path
    assert_response :not_found
  end

  test "hostname defines public and authenticated tenant scope" do
    host! @company_a.platform_domain.hostname
    get public_trip_path(@trip_b[:offer].slug)
    assert_response :not_found
    get public_trip_path(@trip_a[:offer].slug)
    assert_response :success
    get legacy_public_trip_status_path(@company_a.slug, @trip_a[:offer].slug)
    assert_redirected_to public_trip_status_path(@trip_a[:offer].slug)

    login_as(@user)
    get departure_offer_path(@trip_b[:offer])
    assert_response :not_found
  end

  test "user belonging to two companies accesses each only through its hostname" do
    host! @company_a.platform_domain.hostname
    get "/test/sign-in", params: { email: @user.email, role: "admin" }
    get dashboard_path
    assert_response :success
    assert_includes response.body, @company_a.name

    host! @company_b.platform_domain.hostname
    get dashboard_path
    assert_redirected_to root_path
    get "/test/sign-in", params: { email: @user.email, role: "reseller" }
    get dashboard_path
    assert_response :success
    assert_includes response.body, @company_b.name
  end

  test "custom and platform domains resolve the same company" do
    custom = @company_a.company_domains.create!(hostname: "app.agencia-a.example.com", kind: "custom",
      status: "active", verified_at: Time.current, tls_status: "ready", activated_at: Time.current,
      cname_target: "tenants.example.net")
    @company_a.platform_domain.update!(primary: false)
    custom.update!(primary: true)

    [ custom.hostname, @company_a.platform_domain.hostname ].each do |hostname|
      host! hostname
      get public_trip_path(@trip_a[:offer].slug), headers: { "HTTPS" => "on" }
      assert_response :success
    end
    assert_equal "https://#{custom.hostname}/viajes/#{@trip_a[:offer].slug}",
      CompanyUrl.call(@company_a, path: public_trip_path(@trip_a[:offer].slug)).sub("http://", "https://")
  end

  test "custom HTTPS hostname completes centralized OAuth into its own host session" do
    custom = @company_a.company_domains.create!(hostname: "secure.#{SecureRandom.hex(3)}.example.com", kind: "custom",
      status: "active", verified_at: Time.current, tls_status: "ready", activated_at: Time.current,
      cname_target: "tenants.example.net")

    complete_oauth(company: @company_a, user: @user, hostname: custom.hostname)
    get dashboard_path, headers: { "HTTPS" => "on" }

    assert_response :success
    assert_includes response.body, @company_a.name
  end

  test "central OAuth returns to origin with one-time code" do
    exchange_url = complete_oauth(company: @company_a, user: @user)
    assert_redirected_to dashboard_path
    follow_redirect!
    assert_response :success
    assert_includes response.body, @company_a.name

    get URI(exchange_url).request_uri
    assert_response :not_found
  end

  test "OAuth code cannot be exchanged on another company hostname" do
    exchange_url = oauth_exchange_url(company: @company_a, user: @user)
    host! @company_b.platform_domain.hostname
    get URI(exchange_url).request_uri
    assert_response :not_found
  end

  test "Google identity without membership or invitation is rejected" do
    outsider = create_user(name: "Sin acceso")
    callback_location = oauth_callback_location(company: @company_a, user: outsider)

    assert_match %r{\Ahttp://#{Regexp.escape(@company_a.platform_domain.hostname)}/\?auth_error=unauthorized}, callback_location
    assert_not AuthenticationCode.exists?(user: outsider)
  end

  test "invited Google identity receives only the destination membership" do
    invited = create_user(name: "Invitada")
    CompanyInvitation.issue!(company: @company_a, email: invited.email, roles: %w[admin])

    complete_oauth(company: @company_a, user: invited)

    assert @company_a.memberships.exists?(user: invited, status: "active")
    assert_not @company_b.memberships.exists?(user: invited)
  end

  test "expired authentication code and callback outside auth host are rejected" do
    host! @company_a.platform_domain.hostname
    post auth_start_path
    authentication_request = AuthenticationRequest.order(:created_at).last
    _, token = AuthenticationCode.issue!(authentication_request:, user: @user, membership: @membership_a,
      expires_in: -1.second)

    get auth_exchange_path(code: token)
    assert_response :not_found

    post "/auth/google_oauth2/callback"
    assert_response :not_found
  end

  test "only a platform operator can register and activate a custom domain" do
    operator = create_user(name: "Operadora")
    operator.platform_roles.create!(role: "operator")
    login_as(operator)

    hostname = "app.#{SecureRandom.hex(4)}.example.com"
    post platform_company_company_domains_path(@company_a), params: { company_domain: { hostname: } }
    assert_redirected_to platform_companies_path
    domain = @company_a.company_domains.find_by!(hostname:)
    assert_equal "pending", domain.status
    assert domain.verification_token_digest.present?

    domain.update!(status: "verified", verified_at: Time.current, tls_status: "ready")
    post activate_platform_company_company_domain_path(@company_a, domain)
    assert_redirected_to platform_companies_path
    assert_equal "active", domain.reload.status
  end

  test "disabling the primary custom domain restores the permanent platform subdomain" do
    operator = create_user(name: "Operadora de dominios")
    operator.platform_roles.create!(role: "operator")
    custom = @company_a.company_domains.create!(hostname: "recovery.#{SecureRandom.hex(3)}.example.com", kind: "custom",
      status: "active", verified_at: Time.current, tls_status: "ready", activated_at: Time.current,
      cname_target: "tenants.example.net")
    CompanyDomains::MakePrimary.call(company: @company_a, company_domain: custom)
    login_as(operator)

    post disable_platform_company_company_domain_path(@company_a, custom)

    assert_redirected_to platform_companies_path
    assert_equal "disabled", custom.reload.status
    assert @company_a.platform_domain.reload.active?
    assert @company_a.platform_domain.primary?
  end

  test "platform operator also authenticates only through the central host" do
    operator = create_user(name: "Operador OAuth")
    operator.platform_roles.create!(role: "operator")

    complete_oauth(company: nil, user: operator, hostname: PlatformHosts.platform_host)

    assert_redirected_to platform_companies_path
  end

  private

  def complete_oauth(company:, user:, hostname: company&.platform_domain&.hostname || PlatformHosts.platform_host)
    exchange_url = oauth_exchange_url(company:, user:, hostname:)
    host! hostname
    get URI(exchange_url).request_uri
    exchange_url
  end

  def oauth_exchange_url(company:, user:, hostname: company.platform_domain.hostname)
    location = oauth_callback_location(company:, user:, hostname:)
    assert_match "/auth/exchange?code=", location
    location
  end

  def oauth_callback_location(company:, user:, hostname: company.platform_domain.hostname)
    host! hostname
    post auth_start_path
    assert_response :redirect
    continue_url = response.location

    host! PlatformHosts.auth_host
    get URI(continue_url).request_uri
    assert_response :success

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: user.google_sub,
      info: { email: user.email, name: user.name }, extra: { id_info: { email_verified: true } }
    )
    post "/auth/google_oauth2/callback"
    assert_response :redirect
    response.location
  end
end
