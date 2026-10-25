require "test_helper"
require_relative "../support_agent_data"

class ResellerInvitationTest < ActionDispatch::IntegrationTest
  include AgentTestData
  include ActiveJob::TestHelper

  test "operator provisions reseller and verified Google owner accepts invitation on hostname" do
    operator = create_platform_operator
    login_as(operator)
    get new_platform_agent_workspace_path
    assert_response :success
    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
      post platform_agent_workspaces_path, params: { agent_workspace: { business_name: "Silvina Martínez", public_name: "Silvina", subdomain: "silvinamartinez", invited_email: "silvina@example.test", whatsapp: "+541160347665" } }
    end
    workspace = AgentWorkspace.find_by!(subdomain: "silvinamartinez")
    assert_nil workspace.owner_id
    assert_equal "541160347665", workspace.whatsapp
    mail = AgentWorkspaceMailer.invite(workspace)
    assert_equal [ "silvina@example.test" ], mail.to
    assert_includes mail.body.to_s, workspace.hostname
    reset!
    host! workspace.hostname
    get root_path
    assert_response :success
    assert_not_includes response.body, "Cerrar sesión"
    user = create_user(email: "silvina@example.test", name: "Silvina")
    post auth_start_path
    continue_url = response.location
    host! PlatformHosts.auth_host
    get URI(continue_url).request_uri
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: user.google_sub,
      info: { email: user.email, name: user.name }, extra: { id_info: { email_verified: true } })
    post "/auth/google_oauth2/callback"
    assert_equal user.id, workspace.reload.owner_id
    exchange_url = response.location
    host! workspace.hostname
    get URI(exchange_url).request_uri
    assert_redirected_to agent_root_path
    get agent_root_path
    assert_response :success
    assert_empty user.memberships
  ensure
    OmniAuth.config.test_mode = false
  end

  test "wrong identity cannot claim invitation and reseller cannot provision accounts" do
    owner = create_user
    workspace = AgentWorkspace.create!(business_name: "Invitado", public_name: "Invitado", whatsapp: "541160347665", subdomain: "invitado", invited_email: "invited@example.test")
    assert_not workspace.accept_invitation!(owner)
    assert_nil workspace.reload.owner_id
    my_workspace = agent_workspace(owner:)
    login_agent(my_workspace)
    get new_platform_agent_workspace_path
    assert_response :not_found
    my_workspace.update!(status: "suspended")
    get agent_root_path
    assert_response :not_found
  end
end
