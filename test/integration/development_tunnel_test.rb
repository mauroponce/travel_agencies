require "test_helper"

class DevelopmentTunnelTest < ActionDispatch::IntegrationTest
  TUNNEL_HOST = "development-tunnel.ngrok-free.app"

  setup do
    @previous_environment = Rails.env
    @previous_variables = ENV.to_h.slice("PLATFORM_HOST", "AUTH_HOST", "APP_PROTOCOL", "APP_PORT", "AGENT_ENABLED")
    @previous_test_mode = OmniAuth.config.test_mode
    @previous_google_mock = OmniAuth.config.mock_auth[:google_oauth2]
    Rails.env = "development"
    ENV.update("PLATFORM_HOST" => TUNNEL_HOST, "AUTH_HOST" => TUNNEL_HOST,
      "APP_PROTOCOL" => "https", "APP_PORT" => "", "AGENT_ENABLED" => "true")
    host! TUNNEL_HOST
    https!
  end

  teardown do
    Rails.env = @previous_environment
    %w[PLATFORM_HOST AUTH_HOST APP_PROTOCOL APP_PORT AGENT_ENABLED].each do |name|
      @previous_variables.key?(name) ? ENV[name] = @previous_variables[name] : ENV.delete(name)
    end
    OmniAuth.config.test_mode = @previous_test_mode
    OmniAuth.config.mock_auth[:google_oauth2] = @previous_google_mock
  end

  test "localhost redirects to the HTTPS tunnel without the local port and preserves the query" do
    Rails.application.reload_routes!

    %w[localhost 127.0.0.1].each do |hostname|
      host! "#{hostname}:3000"
      https! false
      get "/", params: { from: "local browser" }

      assert_response :found
      assert_redirected_to "https://#{TUNNEL_HOST}/?from=local+browser"
    end

    host! TUNNEL_HOST
    https!
    get URI(response.location).request_uri
    assert_response :success
  ensure
    Rails.env = @previous_environment
    Rails.application.reload_routes!
  end

  test "one HTTPS tunnel serves the platform and completes Google signup without a public port" do
    get root_path
    assert_response :success
    assert_select "a[href=?]", agent_onboarding_path, text: "Crear mi web de agente"

    post auth_start_path, params: { purpose: "agent_onboarding" }
    assert_response :redirect
    continue_url = URI(response.location)
    assert_equal "https", continue_url.scheme
    assert_equal TUNNEL_HOST, continue_url.host
    assert_equal 443, continue_url.port
    assert_equal auth_continue_path, continue_url.path
    get continue_url.request_uri
    assert_response :success
    assert_select "form[action='/auth/google_oauth2'][method=post]"

    uid = "tunnel-#{SecureRandom.hex(8)}"
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid:,
      info: { email: "#{uid}@example.test", name: "Agente del túnel" }, extra: { id_info: { email_verified: true } })
    post "/auth/google_oauth2/callback"
    assert_response :redirect
    exchange_url = URI(response.location)
    assert_equal "https", exchange_url.scheme
    assert_equal TUNNEL_HOST, exchange_url.host
    assert_equal 443, exchange_url.port
    assert_equal auth_exchange_path, exchange_url.path
    get exchange_url.request_uri
    assert_redirected_to agent_onboarding_path
    follow_redirect!
    assert_response :success
    assert_select "input[name='agent_workspace[name]'][value='Agente del túnel']"
    assert_select "input[name='agent_workspace[slug]'][value='agente-del-tunel']"
    assert_select ".agent-public-link span", text: "#{TUNNEL_HOST}/"

    assert_no_difference "HostnameRegistration.count" do
      post agent_onboarding_path, params: { agent_workspace: { name: "Agente del túnel", slug: "agente-del-tunel", whatsapp: "5491155551234" } }
      assert_redirected_to agent_onboarding_path
    end
    follow_redirect!
    assert_select "a[href=?]", "https://#{TUNNEL_HOST}/agente-del-tunel", text: "Ver mi web"
    assert_select "a[href=?]", "https://#{TUNNEL_HOST}/agente", text: "Ingresar a mi espacio"
    get agent_site_path(agent_slug: "agente-del-tunel")
    assert_response :success
    assert_select "h1", text: "Agente del túnel"
    get agent_root_path
    assert_response :success

    get exchange_url.request_uri
    assert_response :not_found
  end

  test "shared host only grants auth scope to central auth routes in development" do
    %w[/ /agente/alta /auth/start /auth/exchange /platform/companies].each do |path|
      assert_equal :platform, TenantResolver.call(TUNNEL_HOST, path:).scope
    end
    %w[/auth/continue /auth/google_oauth2 /auth/google_oauth2/callback /auth/failure].each do |path|
      assert_equal :auth, TenantResolver.call(TUNNEL_HOST, path:).scope
    end

    %w[test staging production].each do |environment|
      Rails.env = environment
      assert_equal :auth, TenantResolver.call(TUNNEL_HOST, path: "/").scope
    end
  end

  test "an unconfigured tunnel cannot access the platform" do
    host! "another-tunnel.ngrok-free.app"
    get root_path
    assert_response :not_found
    post auth_start_path, params: { purpose: "agent_onboarding" }
    assert_response :not_found
  end
end
