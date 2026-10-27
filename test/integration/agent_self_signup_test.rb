require "test_helper"
require_relative "../support_agent_data"

class AgentSelfSignupTest < ActionDispatch::IntegrationTest
  include AgentTestData

  setup do
    @previous_agent_enabled = ENV["AGENT_ENABLED"]
    ENV["AGENT_ENABLED"] = "true"
    @previous_environment = Rails.env
    @previous_omniauth_test_mode = OmniAuth.config.test_mode
    @previous_google_mock = OmniAuth.config.mock_auth[:google_oauth2]
    OmniAuth.config.test_mode = true
    @google_uid = "signup-#{SecureRandom.hex(8)}"
    @google_email = "#{@google_uid}@example.test"
  end

  teardown do
    @previous_agent_enabled ? ENV["AGENT_ENABLED"] = @previous_agent_enabled : ENV.delete("AGENT_ENABLED")
    Rails.env = @previous_environment
    OmniAuth.config.test_mode = @previous_omniauth_test_mode
    OmniAuth.config.mock_auth[:google_oauth2] = @previous_google_mock
  end

  test "new Google agent registers a subdomain and manually publishes a trip to anonymous visitors" do
    host! PlatformHosts.platform_host
    get root_path
    assert_select "a[href=?]", agent_onboarding_path, text: "Crear mi web de agente"
    assert_select "form[action=?][method=post]", auth_start_path(purpose: "agent_onboarding"), count: 2 do
      assert_select "button[data-turbo=false]", text: "Registrarme con Google"
    end
    assert_select ".nav-actions form[action=?]", auth_start_path do
      assert_select "button", text: "Ingresar con Google"
    end
    assert_difference "User.count", 1 do
      google_login(hostname: PlatformHosts.platform_host, purpose: "agent_onboarding")
    end
    user = User.find_by!(google_sub: @google_uid)
    assert_empty user.memberships
    assert_not user.platform_operator?

    assert_difference [ "AgentWorkspace.count", "HostnameRegistration.count" ], 1 do
      post agent_onboarding_path, params: signup_params
      assert_redirected_to agent_onboarding_path
    end
    workspace = user.reload.agent_workspace
    assert_equal "silvinamartinez.#{PlatformHosts.base_domain}", workspace.hostname
    assert_equal workspace.id, TenantResolver.call(workspace.hostname).agent_workspace.id
    follow_redirect!
    assert_select "a[href=?]", workspace.url, text: "Ver mi web"
    assert_select "a[href=?]", workspace.url(path: agent_root_path), text: "Ingresar a mi espacio"

    google_login(hostname: workspace.hostname)
    get new_agent_trip_path
    assert_response :success
    assert_difference "workspace.agent_trips.count", 1 do
      post agent_trips_path, params: { commit_action: "draft", agent_trip_revision: {
        new_supplier_name: "Operador de Silvina", title: "Vacaciones en Bariloche", destination: "Bariloche",
        departs_on: 2.months.from_now.to_date, price: "850.000,50", currency: "ARS", price_unit: "per_person",
        description: "Una semana en la Patagonia", cover: png_upload
      } }
      assert_response :redirect
    end
    trip = workspace.agent_trips.last
    assert_equal 85_000_050, trip.current_revision.price_cents

    visitor = open_session
    visitor.host! workspace.hostname
    visitor.get root_path
    visitor.assert_response :success
    visitor.assert_select "h1", text: "Silvina Martínez Viajes"
    visitor.assert_select "a[href=?]", agent_public_trip_path(slug: trip.slug), count: 0

    post publish_agent_trip_path(trip)
    assert_redirected_to agent_trip_path(trip)
    visitor.get root_path
    visitor.assert_select "a[href=?]", agent_public_trip_path(slug: trip.slug), text: "Vacaciones en Bariloche"
    visitor.get agent_public_trip_path(slug: trip.slug)
    visitor.assert_response :success
    visitor.assert_includes visitor.response.body, "850.000,50"
    visitor.assert_select "a[href^='https://wa.me/5491155551234']"
    visitor.get agent_public_image_path(slug: trip.slug, revision_id: trip.reload.published_revision_id)
    visitor.assert_response :success
    assert_equal File.binread(Rails.root.join("test/fixtures/files/agent.png")), visitor.response.body

    post unpublish_agent_trip_path(trip)
    visitor.get agent_public_trip_path(slug: trip.slug)
    visitor.assert_response :not_found
    visitor.get root_path
    visitor.assert_select "a[href=?]", agent_public_trip_path(slug: trip.slug), count: 0
  end

  test "self signup and Google onboarding are available in staging and production after host finalization" do
    %w[staging production].each do |environment|
      Rails.env = environment
      @google_uid = "#{@google_uid}-#{environment}"
      @google_email = "#{@google_uid}@example.test"
      assert AgentWorkspace.self_signup_enabled?
      google_login(hostname: PlatformHosts.platform_host, purpose: "agent_onboarding")
      get agent_onboarding_path
      assert_response :success
      assert_select "input[name='agent_workspace[subdomain]']"
      assert_difference "AgentWorkspace.count", 1 do
        post agent_onboarding_path, params: signup_params(subdomain: "silvina-#{environment}")
        assert_redirected_to agent_onboarding_path
      end
      workspace = User.find_by!(google_sub: @google_uid).agent_workspace
      reset!
      host! workspace.hostname
      get root_path
      assert_response :success
      assert_select "h1", text: "Silvina Martínez Viajes"
    end
  end

  test "disabled agent module hides signup and rejects registration and pending OAuth exchange" do
    host! PlatformHosts.platform_host
    post auth_start_path, params: { purpose: "agent_onboarding" }
    continue_url = response.location
    host! PlatformHosts.auth_host
    get URI(continue_url).request_uri
    mock_google_identity
    post "/auth/google_oauth2/callback"
    exchange_url = response.location
    assert_includes exchange_url, "/auth/exchange?code="

    ENV["AGENT_ENABLED"] = "false"
    host! PlatformHosts.platform_host
    get URI(exchange_url).request_uri
    assert_response :forbidden
    get root_path
    assert_response :success
    assert_select "a[href=?]", agent_onboarding_path, count: 0
    assert_select "form[action=?]", auth_start_path(purpose: "agent_onboarding"), count: 0
    assert_select "form[action=?]", auth_start_path, count: 3
    get agent_onboarding_path
    assert_response :not_found
    assert_no_difference "AgentWorkspace.count" do
      post agent_onboarding_path, params: signup_params
      assert_response :not_found
    end
  end

  test "subdomains cannot be reserved or owned by another agent and a user cannot register twice" do
    google_login(hostname: PlatformHosts.platform_host, purpose: "agent_onboarding")
    existing = agent_workspace
    [ "auth", existing.subdomain ].each do |subdomain|
      assert_no_difference [ "AgentWorkspace.count", "HostnameRegistration.count" ] do
        post agent_onboarding_path, params: signup_params(subdomain:)
        assert_response :unprocessable_entity
        assert_select "input[name='agent_workspace[business_name]'][value='Silvina Martínez Viajes']"
      end
    end
    post agent_onboarding_path, params: signup_params
    assert_redirected_to agent_onboarding_path
    assert_no_difference [ "AgentWorkspace.count", "HostnameRegistration.count" ] do
      post agent_onboarding_path, params: signup_params(subdomain: "segunda-web")
      assert_redirected_to agent_onboarding_path
    end
  end

  test "Google email must be verified before a new agent can register" do
    host! PlatformHosts.platform_host
    post auth_start_path, params: { purpose: "agent_onboarding" }
    continue_url = response.location
    host! PlatformHosts.auth_host
    get URI(continue_url).request_uri
    mock_google_identity(verified: false)
    assert_no_difference [ "User.count", "AgentWorkspace.count" ] do
      post "/auth/google_oauth2/callback"
      assert_response :redirect
      assert_includes response.location, "auth_error=unauthorized"
    end
    host! PlatformHosts.platform_host
    post agent_onboarding_path, params: signup_params
    assert_redirected_to agent_onboarding_path
    assert_nil User.find_by(google_sub: @google_uid)
  end

  private

  def signup_params(subdomain: "silvinamartinez")
    { agent_workspace: { business_name: "Silvina Martínez Viajes", public_name: "Silvina Martínez",
      whatsapp: "+54 9 11 5555 1234", subdomain:, presentation: "Viajes con atención personal" } }
  end

  def mock_google_identity(verified: true)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: @google_uid,
      info: { email: @google_email, name: "Silvina Martínez" }, extra: { id_info: { email_verified: verified } })
  end

  def google_login(hostname:, purpose: nil)
    host! hostname
    post auth_start_path, params: { purpose: }.compact
    assert_response :redirect
    continue_url = response.location
    host! PlatformHosts.auth_host
    get URI(continue_url).request_uri
    assert_response :success
    mock_google_identity
    post "/auth/google_oauth2/callback"
    assert_response :redirect
    exchange_url = response.location
    assert_includes exchange_url, "/auth/exchange?code="
    host! hostname
    get URI(exchange_url).request_uri
    assert_redirected_to(purpose == "agent_onboarding" ? agent_onboarding_path : agent_root_path)
  end
end
