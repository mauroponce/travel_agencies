require "test_helper"
require_relative "../support_agent_data"

class AgentWorkspaceTest < ActionDispatch::IntegrationTest
  include AgentTestData

  test "Google identity can onboard without a company membership" do
    user = create_user
    host! PlatformHosts.platform_host
    get agent_onboarding_path
    assert_response :success
    get "/test/sign-in", params: { email: user.email, purpose: "agent_onboarding" }
    assert_redirected_to agent_onboarding_path
    assert_difference "AgentWorkspace.count", 1 do
      post agent_onboarding_path, params: { agent_workspace: { business_name: "Mi agencia independiente", public_name: "Lucía", whatsapp: "+54 9 11 5555 1234", subdomain: "lucia-#{SecureRandom.hex(3)}" } }
    end
    assert_empty user.memberships
    get agent_onboarding_path
    assert_response :success
    assert_includes response.body, "Ingresar a mi espacio"
    login_agent(user.reload.agent_workspace)
    get agent_root_path
    assert_response :success
    assert_includes response.body, "Piloto de lanzamiento"
  end

  test "central OAuth supports onboarding and agent access without platform permissions" do
    workspace = agent_workspace
    [ [ :onboarding, PlatformHosts.platform_host ], [ :agent, workspace.hostname ] ].each do |kind, hostname|
      host! hostname
      post auth_start_path, params: kind == :onboarding ? { purpose: "agent_onboarding" } : {}
      assert_response :redirect
      continue_url = response.location
      host! PlatformHosts.auth_host
      get URI(continue_url).request_uri
      assert_response :success
      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: workspace.owner.google_sub,
        info: { email: workspace.owner.email, name: workspace.owner.name }, extra: { id_info: { email_verified: true } })
      post "/auth/google_oauth2/callback"
      assert_response :redirect
      exchange_url = response.location
      assert_includes exchange_url, "/auth/exchange?code="
      host! hostname
      get URI(exchange_url).request_uri
      assert_redirected_to(kind == :onboarding ? agent_onboarding_path : agent_root_path)
      get URI(exchange_url).request_uri
      assert_response :not_found
    end
    host! PlatformHosts.platform_host
    get platform_companies_path
    assert_redirected_to root_path
    assert_not workspace.owner.platform_operator?
  ensure
    OmniAuth.config.test_mode = false
  end

  test "supplier CRUD and ten providers are private to their workspace" do
    workspace = agent_workspace
    other = agent_workspace
    foreign = other.agent_suppliers.create!(name: "Privado")
    login_agent(workspace)
    10.times do |i|
      post agent_suppliers_path, params: { agent_supplier: { name: "Empresa #{i}", commission_terms: "15%", contact_name: "Contacto" } }
      assert_response :redirect
    end
    assert_equal 10, workspace.agent_suppliers.count
    supplier = workspace.agent_suppliers.first
    get agent_suppliers_path(q: "Contacto")
    assert_response :success
    assert_includes response.body, supplier.name
    patch agent_supplier_path(supplier), params: { agent_supplier: { status: "paused" } }
    assert_equal "paused", supplier.reload.status
    get edit_agent_supplier_path(supplier)
    assert_response :success
    get agent_supplier_path(foreign)
    assert_response :not_found
    patch agent_supplier_path(foreign), params: { agent_supplier: { name: "Intrusión" } }
    assert_response :not_found
  end

  test "manual trip flows and public revisions use the agent WhatsApp" do
    workspace = agent_workspace
    supplier = workspace.agent_suppliers.create!(name: "Operador", phone: "5491112349999", commercial_terms: "SECRETO COMERCIAL", commission_terms: "COMISIÓN PRIVADA")
    login_agent(workspace)
    get new_agent_trip_path
    assert_response :success
    post agent_trips_path, params: { agent_trip_revision: { agent_supplier_id: supplier.id, title: "Córdoba especial", destination: "Córdoba", departs_on: 1.month.from_now.to_date, price: "500000", currency: "ARS", price_unit: "per_person" }, commit_action: "publish" }
    assert_response :redirect
    trip = workspace.agent_trips.last
    get agent_trip_path(trip)
    assert_response :success
    get edit_agent_trip_path(trip)
    assert_response :success
    patch agent_trip_path(trip), params: { expected_revision_id: trip.current_revision_id, agent_trip_revision: trip.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("price" => "600000"), commit_action: "draft" }
    assert_response :redirect
    get agent_public_trip_path(slug: trip.slug)
    assert_response :success
    assert_includes response.body, "500.000"
    assert_not_includes response.body, "600.000"
    assert_includes response.body, "https://wa.me/#{workspace.whatsapp}"
    assert_not_includes response.body, supplier.phone
    assert_not_includes response.body, "SECRETO COMERCIAL"
    assert_not_includes response.body, "COMISIÓN PRIVADA"
    post publish_agent_trip_path(trip)
    get agent_public_trip_path(slug: trip.slug)
    assert_includes response.body, "600.000"
    supplier.update!(status: "paused")
    get agent_public_trip_path(slug: trip.slug)
    assert_response :not_found
    supplier.update!(status: "active")
    get root_path
    assert_response :success
    assert_includes response.body, "Córdoba especial"
  end

  test "public visitors see only live trips and cannot read private routes" do
    workspace = agent_workspace
    published = agent_trip(workspace:)
    published.publish!
    draft = agent_trip(workspace:, title: "BORRADOR PRIVADO")
    host! workspace.hostname
    get root_path
    assert_response :success
    assert_includes response.body, published.current_revision.title
    assert_not_includes response.body, "BORRADOR PRIVADO"
    get agent_public_trip_path(slug: draft.slug)
    assert_response :not_found
    get agent_suppliers_path
    assert_redirected_to root_path
    workspace.update!(status: "suspended")
    get root_path
    assert_response :not_found
  end

  test "another agent cannot read trips imports comparisons or private source" do
    owner = agent_workspace
    other = agent_workspace
    trip = agent_trip(workspace: owner)
    second = agent_trip(workspace: other)
    import = owner.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload)
    login_agent(other)
    [ agent_trip_path(trip), edit_agent_trip_path(trip), source_agent_import_path(import), agent_import_path(import), compare_agent_trips_path(ids: [ trip.id, second.id ]) ].each do |path|
      get path
      assert_response :not_found
    end
    host! owner.hostname
    get agent_root_path
    assert_redirected_to root_path
    get "/test/sign-in", params: { email: other.owner.email }
    assert_response :forbidden
  end

  test "website preview uses public data and same origin frame permission" do
    workspace = agent_workspace
    login_agent(workspace)
    get agent_website_path
    assert_response :success
    patch agent_website_path, params: { agent_workspace: { business_name: "Nueva marca", whatsapp: "5491155551234" } }
    assert_response :redirect
    get preview_agent_website_path
    assert_response :success
    assert_includes response.headers["Content-Security-Policy"], "frame-ancestors 'self'"
    assert_includes response.body, "Nueva marca"
    get pwa_manifest_path(format: :json)
    assert_response :success
    assert_equal "agent-#{workspace.id}", response.parsed_body["id"]
    get pwa_service_worker_path
    assert_response :success
    assert_includes response.body, 'path.startsWith("/assets/")'
  end

  test "operator can suspend agents without granting the owner platform access" do
    workspace = agent_workspace
    operator = create_platform_operator
    login_as(operator)
    get platform_agent_workspaces_path
    assert_response :success
    patch platform_agent_workspace_path(workspace), params: { agent_workspace: { status: "suspended" } }
    assert_equal "suspended", workspace.reload.status
  end

  test "TLS ask is authenticated and only permits registered active agent hosts" do
    workspace = agent_workspace
    ENV["CADDY_ASK_SECRET"] = "test-secret"
    host! PlatformHosts.platform_host
    get "/internal/tls/authorize", params: { domain: workspace.hostname }
    assert_response :forbidden
    get "/internal/tls/authorize", params: { domain: workspace.hostname, token: "test-secret" }
    assert_response :no_content
    get "/internal/tls/authorize", params: { domain: "unknown.example.test", token: "test-secret" }
    assert_response :forbidden
    workspace.update!(status: "suspended")
    get "/internal/tls/authorize", params: { domain: workspace.hostname, token: "test-secret" }
    assert_response :forbidden
  ensure
    ENV.delete("CADDY_ASK_SECRET")
  end
end
