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

  test "new Google agent registers a public slug and manually publishes a trip to anonymous visitors" do
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

    assert_difference "AgentWorkspace.count", 1 do
      post agent_onboarding_path, params: signup_params
      assert_redirected_to agent_root_path
    end
    workspace = user.reload.agent_workspace
    assert_equal "silvina-martinez", workspace.slug
    assert_nil workspace.subdomain
    assert_nil workspace.hostname_registration
    assert_equal PlatformHosts.url(host: PlatformHosts.platform_host, path: "/silvina-martinez"), workspace.url
    follow_redirect!
    assert_response :success
    assert_select "h1", text: "Todo listo para tu próximo viaje"
    assert_select "a[href=?]", workspace.url, text: "Ver mi web ↗"

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
    visitor.host! PlatformHosts.platform_host
    visitor.get agent_site_path(agent_slug: workspace.slug)
    visitor.assert_response :success
    visitor.assert_select "h1", text: "Silvina Martínez Viajes"
    visitor.assert_select "a[href=?]", workspace.url(path: agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)), count: 0

    post publish_agent_trip_path(trip)
    assert_redirected_to agent_trip_path(trip)
    visitor.get agent_site_path(agent_slug: workspace.slug)
    visitor.assert_select "a[href=?]", workspace.url(path: agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)), text: "Vacaciones en Bariloche"
    visitor.get agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)
    visitor.assert_response :success
    visitor.assert_includes visitor.response.body, "850.000,50"
    visitor.assert_select "a[href^='https://wa.me/5491155551234']"
    visitor.get agent_site_image_path(agent_slug: workspace.slug, slug: trip.slug, revision_id: trip.reload.published_revision_id)
    visitor.assert_response :success
    assert_equal File.binread(Rails.root.join("test/fixtures/files/agent.png")), visitor.response.body

    post unpublish_agent_trip_path(trip)
    visitor.get agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)
    visitor.assert_response :not_found
    visitor.get agent_site_path(agent_slug: workspace.slug)
    visitor.assert_select "a[href=?]", workspace.url(path: agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)), count: 0
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
      assert_select "input[name='agent_workspace[slug]']"
      assert_difference "AgentWorkspace.count", 1 do
        post agent_onboarding_path, params: signup_params(slug: "silvina-#{environment}")
        assert_redirected_to agent_root_path
      end
      workspace = User.find_by!(google_sub: @google_uid).agent_workspace
      reset!
      host! PlatformHosts.platform_host
      get agent_site_path(agent_slug: workspace.slug)
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

  test "slugs cannot be reserved or owned by another agent and a user cannot register twice" do
    google_login(hostname: PlatformHosts.platform_host, purpose: "agent_onboarding")
    existing = agent_workspace
    [ "auth", existing.slug ].each do |slug|
      assert_no_difference [ "AgentWorkspace.count", "HostnameRegistration.count" ] do
        post agent_onboarding_path, params: signup_params(slug:)
        assert_response :unprocessable_entity
        assert_select "input[name='agent_workspace[name]'][value='Silvina Martínez Viajes']"
      end
    end
    post agent_onboarding_path, params: signup_params
    assert_redirected_to agent_root_path
    assert_no_difference [ "AgentWorkspace.count", "HostnameRegistration.count" ] do
      post agent_onboarding_path, params: signup_params(slug: "segunda-web")
      assert_redirected_to agent_root_path
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

  test "Google name is editable and the form contains one name and a unique path suggestion" do
    agent_workspace(slug: "silvina-martinez")
    google_login(hostname: PlatformHosts.platform_host, purpose: "agent_onboarding")
    get agent_onboarding_path
    assert_response :success
    assert_select "label[for=agent_workspace_name]", text: "Nombre"
    assert_select "input[name='agent_workspace[name]'][value='Silvina Martínez']"
    assert_select "input[name='agent_workspace[slug]'][value='silvina-martinez-2']"
    assert_select "input[name='agent_workspace[business_name]']", count: 0
    assert_select "input[name='agent_workspace[public_name]']", count: 0
    assert_select "input[name='agent_workspace[subdomain]']", count: 0
    assert_select ".agent-public-link span", text: "#{PlatformHosts.platform_host}/"
    assert_select "small", text: /\.lvh\.me/, count: 0

    get suggestion_agent_onboarding_path, params: { name: "José Pérez" }
    assert_equal "jose-perez", response.parsed_body["slug"]
    assert_includes response.headers["Cache-Control"], "no-store"
    get suggestion_agent_onboarding_path, params: { slug: "silvina-martinez" }
    assert_equal false, response.parsed_body["available"]
    assert_equal "silvina-martinez-2", response.parsed_body["slug"]

    signup_attributes = signup_params(slug: "mi-marca")
    signup_attributes[:agent_workspace][:name] = "Mi nombre elegido"
    post agent_onboarding_path, params: signup_attributes
    assert_redirected_to agent_root_path
    workspace = User.find_by!(google_sub: @google_uid).agent_workspace
    assert_equal "Mi nombre elegido", workspace.name
    assert_equal workspace.name, workspace.public_name
    assert_equal "mi-marca", workspace.slug
    get agent_root_path
    assert_response :success
    get agent_website_path
    assert_select "input[name='agent_workspace[name]'][value='Mi nombre elegido']"
  end

  test "a slug claimed after its suggestion returns an alternative and preserves all entered data" do
    google_login(hostname: PlatformHosts.platform_host, purpose: "agent_onboarding")
    get suggestion_agent_onboarding_path, params: { name: "Silvina Martínez" }
    proposed = response.parsed_body["slug"]
    agent_workspace(slug: proposed)
    assert_no_difference [ "AgentWorkspace.count", "HostnameRegistration.count" ] do
      post agent_onboarding_path, params: signup_params(slug: proposed)
      assert_response :unprocessable_entity
    end
    assert_select "input[name='agent_workspace[name]'][value='Silvina Martínez Viajes']"
    assert_select "input[name='agent_workspace[slug]'][value=?]", proposed
    assert_select "input[name='agent_workspace[whatsapp]'][value='+54 9 11 5555 1234']"
    assert_select "textarea[name='agent_workspace[presentation]']", count: 0
    assert_select "[role=alert]", text: /ya está en uso/
    assert_select "button[data-slug=?]:not([hidden])", "#{proposed}-2", text: "Usar #{proposed}-2"
    post agent_onboarding_path, params: signup_params(slug: "#{proposed}-2")
    assert_redirected_to agent_root_path
  end

  test "name errors use the single visible field label and preserve a custom link" do
    google_login(hostname: PlatformHosts.platform_host, purpose: "agent_onboarding")
    attributes = signup_params(slug: "mi-link-elegido")
    attributes[:agent_workspace][:name] = "  "
    post agent_onboarding_path, params: attributes
    assert_response :unprocessable_entity
    assert_select "[role=alert] li", text: "Nombre no puede estar vacío", count: 1
    assert_select "input[name='agent_workspace[slug]'][value='mi-link-elegido']"
  end

  test "slug routes isolate public catalogs from private workspaces and reject suspended and unknown slugs" do
    own = agent_workspace(subdomain: nil, slug: "propio")
    other = agent_workspace(subdomain: nil, slug: "ajeno")
    trip = agent_trip(workspace: other)
    trip.publish!
    host! PlatformHosts.platform_host
    get suggestion_agent_onboarding_path, params: { name: "Persona" }
    assert_response :unauthorized
    get agent_site_path(agent_slug: own.slug)
    assert_response :success
    get agent_site_trip_path(agent_slug: own.slug, slug: trip.slug)
    assert_response :not_found
    get agent_site_trip_path(agent_slug: other.slug, slug: trip.slug)
    assert_response :success
    get agent_root_path
    assert_redirected_to root_path

    get "/test/sign-in", params: { email: own.owner.email }
    get agent_site_path(agent_slug: other.slug)
    assert_response :success
    get agent_trip_path(trip)
    assert_response :not_found
    get agent_root_path
    assert_response :success
    assert_select ".topbar-actions strong", text: own.name
    other.update!(status: "suspended")
    get agent_site_path(agent_slug: other.slug)
    assert_response :not_found
    get agent_site_path(agent_slug: "no-existe")
    assert_response :not_found
    ENV["AGENT_ENABLED"] = "false"
    get agent_site_path(agent_slug: own.slug)
    assert_response :not_found
  end

  test "an existing agent can sign in from the platform without a subdomain or operator permissions" do
    mock_google_identity
    user = Auth::GoogleIdentity.call(OmniAuth.config.mock_auth[:google_oauth2])
    workspace = agent_workspace(owner: user, subdomain: nil, slug: "google-agent")
    google_login(hostname: PlatformHosts.platform_host)
    get agent_root_path
    assert_response :success
    assert_select "a[href=?]", workspace.url, text: "Ver mi web ↗"
    get platform_companies_path
    assert_redirected_to root_path
    assert_not user.platform_operator?
  end

  private

  def signup_params(slug: "silvina-martinez")
    { agent_workspace: { name: "Silvina Martínez Viajes",
      whatsapp: "+54 9 11 5555 1234", slug: } }
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
