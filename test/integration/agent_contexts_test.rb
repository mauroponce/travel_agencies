require "test_helper"
require_relative "../support_agent_data"

class AgentContextsTest < ActionDispatch::IntegrationTest
  include AgentTestData

  setup do
    @user = create_user
    @companies = 3.times.map { |i| Company.create!(name: "Empresa #{i}", slug: "acceso-#{i}-#{SecureRandom.hex(4)}") }
    @memberships = @companies.first(2).map { |company| create_membership(company:, user: @user, roles: %w[reseller]) }
    @unauthorized = create_membership(company: @companies.last, user: create_user, roles: %w[admin])
    @previous_mode = OmniAuth.config.test_mode
    @previous_mock = OmniAuth.config.mock_auth[:google_oauth2]
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: @user.google_sub,
      info: { email: @user.email, name: @user.name }, extra: { id_info: { email_verified: true } })
  end

  teardown do
    OmniAuth.config.test_mode = @previous_mode
    OmniAuth.config.mock_auth[:google_oauth2] = @previous_mock
  end

  def google_login(host)
    host! host
    post auth_start_path
    entry = response.location
    host! PlatformHosts.auth_host
    get URI(entry).request_uri
    post "/auth/google_oauth2/callback"
    exchange = response.location
    return exchange unless URI(exchange).path == auth_exchange_path
    host! host
    get URI(exchange).request_uri
  end

  test "general Google login lists two companies without creating Pro and each host authorizes only its membership" do
    assert_no_difference [ "AgentWorkspace.count", "AgentSubscription.count" ] do
      google_login(PlatformHosts.platform_host)
    end
    assert_redirected_to context_path
    follow_redirect!
    assert_response :success
    @companies.first(2).each { |company| assert_includes response.body, company.name }
    assert_not_includes response.body, @companies.last.name
    post context_path, params: { membership_id: @unauthorized.id }
    assert_response :not_found
    post context_path, params: { membership_id: @memberships.first.id }
    assert_redirected_to CompanyUrl.call(@companies.first)
    @companies.first(2).each do |company|
      google_login(company.platform_domain.hostname)
      assert_redirected_to dashboard_path
      get dashboard_path
      assert_response :success
      get agent_clients_path
      assert_response :not_found
    end
    rejected = google_login(@companies.last.platform_domain.hostname)
    assert_includes rejected, "auth_error=unauthorized"
    assert_nil @user.reload.agent_workspace
  end

  test "revoked memberships and suspended companies are revalidated on context switch" do
    google_login(PlatformHosts.platform_host)
    @memberships.first.update!(status: "revoked")
    post context_path, params: { membership_id: @memberships.first.id }
    assert_response :not_found
    @companies.second.update!(status: "suspended")
    post context_path, params: { membership_id: @memberships.second.id }
    assert_response :forbidden
    get context_path
    assert_not_includes response.body, @companies.second.name
  end

  test "a personal workspace and Pro expiry never grant or revoke company roles" do
    workspace = agent_workspace(owner: @user, subdomain: nil)
    workspace.agent_subscription.update!(trial_starts_at: 20.days.ago, trial_ends_at: 1.day.ago)
    google_login(PlatformHosts.platform_host)
    assert_redirected_to agent_root_path
    get root_path
    assert_redirected_to agent_root_path
    get context_path
    assert_redirected_to agent_root_path
    follow_redirect!
    assert_response :success
    assert_select "h1", text: "Todo listo para tu próximo viaje"
    get platform_agent_workspaces_path
    assert_redirected_to root_path
    google_login(@companies.first.platform_domain.hostname)
    get dashboard_path
    assert_response :success
    post context_path, params: { role: "admin" }
    assert_response :forbidden
    assert_not @memberships.first.role?("admin")
  end

  test "a personal workspace goes straight home from Google login and the platform root" do
    workspace = agent_workspace(owner: @user, subdomain: nil)
    assert_no_difference [ "AgentWorkspace.count", "AgentSubscription.count" ] do
      google_login(PlatformHosts.platform_host)
      assert_redirected_to agent_root_path
      get root_path
      assert_redirected_to agent_root_path
      get context_path
      assert_redirected_to agent_root_path
    end
    assert_equal workspace.id, @user.reload.agent_workspace.id
    assert_equal 2, @user.memberships.active.count
  end

  test "users without a personal workspace keep company selection and operators keep their dashboard" do
    google_login(PlatformHosts.platform_host)
    get root_path
    assert_redirected_to context_path
    workspace = agent_workspace(owner: @user, subdomain: nil)
    workspace.update!(status: "suspended")
    get root_path
    assert_redirected_to context_path
    get context_path
    assert_response :success
    assert_includes response.body, "Tu espacio personal está suspendido"
    operator = create_platform_operator
    get "/test/sign-in", params: { email: operator.email }
    assert_redirected_to platform_companies_path
    get root_path
    assert_redirected_to platform_companies_path
  end
end
