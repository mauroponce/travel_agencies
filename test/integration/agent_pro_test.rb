require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentProTest < ActionDispatch::IntegrationTest
  include AgentTestData
  include ActiveJob::TestHelper

  setup do
    @workspace = agent_workspace(subdomain: nil)
    @trip = agent_trip(workspace: @workspace, cover: png_upload)
    @trip.publish!
    @client = @workspace.agent_clients.create!(name: "Persona privada", phone: "+54 9 11 5555 1234")
    @client.notes.create!(agent_workspace: @workspace, body: "NOTA PRIVADA", agent_trip: @trip)
    @subscription = @workspace.agent_subscription
  end

  def expire!
    @subscription.update!(trial_starts_at: 20.days.ago, trial_ends_at: 1.second.ago)
  end

  test "plan pages and self service actions are removed while expired accounts retain useful guidance" do
    login_agent(@workspace)
    get agent_root_path
    assert_response :success
    assert_select "#main-sidebar a", text: "Mi plan", count: 0
    assert_select "a[href^='/asesor/mi-plan']", count: 0
    original = @subscription.attributes
    get "/asesor/mi-plan"
    assert_response :not_found
    %w[solicitar-activacion cancelar].each do |action|
      post "/asesor/mi-plan/#{action}", params: { status: "active", price_cents: 0 }
      assert_response :not_found
    end
    assert_equal original, @subscription.reload.attributes
    expire!
    get agent_trips_path
    assert_response :success
    assert_select "[role=status]", text: /Coordiná la reactivación con la administración de Turistack/
    assert_select "a[href^='/asesor/mi-plan']", count: 0
  end

  test "onboarding replay never recreates a trial or accepts commercial parameters" do
    login_agent(@workspace)
    original_end = @subscription.trial_ends_at
    assert_no_difference [ "AgentWorkspace.count", "AgentSubscription.count" ] do
      post agent_onboarding_path, params: { agent_workspace: { name: "Otra marca", slug: "otro", whatsapp: "5491155551234", plan: "pro" } }
    end
    assert_equal original_end, @subscription.reload.trial_ends_at
    patch agent_website_path, params: { agent_workspace: { name: @workspace.name, status: "active", price_cents: 0, trial_ends_at: 10.years.from_now } }
    assert_response :redirect
    assert_equal 1900, @subscription.reload.price_cents
    assert_equal original_end, @subscription.trial_ends_at
    post platform_agent_workspace_subscription_path(@workspace)
    assert_redirected_to root_path
    assert_equal "trialing", @subscription.reload.status
    assert_raises(Pundit::NotAuthorizedError) { Agent::Subscriptions.grant_month!(workspace: @workspace, actor: @workspace.owner) }
  end

  test "expiration retains private reading export and memberships while denying every commercial entry" do
    company = Company.create!(name: "Acceso empresarial", slug: "empresa-#{SecureRandom.hex(4)}")
    create_membership(company:, user: @workspace.owner, roles: %w[reseller])
    expire!
    login_agent(@workspace)
    [ agent_root_path, agent_trips_path, agent_trip_path(@trip), agent_clients_path, agent_client_path(@client), source_agent_trip_path(@trip) ].each do |path|
      get path
      assert_response :success
    end
    get agent_export_path(format: :json)
    assert_response :success
    assert_equal "Persona privada", response.parsed_body["clients"].first["name"]
    get export_agent_clients_path(format: :csv, notes: "1")
    assert_response :success
    assert_includes response.body, "NOTA PRIVADA"
    assert_includes response.headers["Cache-Control"], "no-store"
    [ new_agent_trip_path, edit_agent_trip_path(@trip), preview_agent_website_path ].each do |path|
      get path
      assert_response :forbidden
    end
    post publish_agent_trip_path(@trip)
    assert_response :forbidden
    patch agent_website_path, params: { agent_workspace: { name: "Cambio prohibido" } }
    assert_response :forbidden
    post agent_suppliers_path, params: { agent_supplier: { name: "Prohibido" } }
    assert_response :forbidden
    patch agent_client_path(@client), params: { agent_client: { name: "Prohibido" } }
    assert_response :forbidden
    post agent_client_notes_path(@client), params: { agent_client_note: { body: "Prohibido" } }
    assert_response :forbidden
    post agent_trip_imports_path, params: { source: png_upload, idempotency_key: SecureRandom.uuid }
    assert_response :forbidden
    assert_equal "trialing", @subscription.status
    assert_not @subscription.entitled?
    host! company.platform_domain.hostname
    get "/test/sign-in", params: { email: @workspace.owner.email, role: "reseller" }
    get dashboard_path
    assert_response :success
    assert @workspace.owner.memberships.first.active?
  end

  test "public URLs search photos and images close at expiry and reactivation restores only the published revision" do
    original_id = @trip.published_revision_id
    Agent::SaveTrip.call(workspace: @workspace, trip: @trip, attributes: @trip.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "BORRADOR OCULTO"))
    @workspace.update!(show_about: true, about_photo: png_upload)
    expire!
    host! PlatformHosts.platform_host
    paths = [ agent_site_path(agent_slug: @workspace.slug), agent_site_trip_path(agent_slug: @workspace.slug, slug: @trip.slug),
      agent_site_search_path(agent_slug: @workspace.slug, q: "Córdoba"),
      agent_site_image_path(agent_slug: @workspace.slug, slug: @trip.slug, revision_id: original_id),
      agent_site_about_photo_path(agent_slug: @workspace.slug, blob_id: @workspace.about_photo.blob_id) ]
    paths.each { |path| get path; assert_response :not_found }
    assert_empty Agent::CatalogQuery.call(workspace: @workspace, public_view: true)
    assert_raises(Pundit::NotAuthorizedError) { @trip.publish! }
    assert_raises(Pundit::NotAuthorizedError) { agent_trip(workspace: @workspace) }
    assert_raises(Pundit::NotAuthorizedError) { @client.update!(name: "No") }
    task = @workspace.agent_imports.create!(idempotency_key: "expired-job", source: png_upload)
    assert_no_difference "AgentAiExecution.count" do
      AgentAiJob.perform_now("import", task.id)
    end
    assert_equal "plan_expired", task.reload.error_code
    assert task.source.attached?
    Agent::Subscriptions.grant_month!(workspace: @workspace, actor: create_platform_operator)
    paths.each { |path| get path; assert_response :success }
    get paths[1]
    assert_not_includes response.body, "BORRADOR OCULTO"
    assert_not_includes response.body, "NOTA PRIVADA"
    assert_equal original_id, @trip.reload.published_revision_id
    assert_includes response.body, "wa.me/#{@workspace.whatsapp}"
  end

  test "operator manual grant renews calendar months audits and preserves administrative suspension" do
    operator = create_platform_operator
    login_as(operator)
    post platform_agent_workspace_subscription_path(@workspace), params: { price_cents: 0, current_period_ends_at: 20.years.from_now }
    assert_response :redirect
    first_end = @subscription.reload.current_period_ends_at
    assert_equal 1900, @subscription.price_cents
    post platform_agent_workspace_subscription_path(@workspace)
    assert_equal first_end.advance(months: 1), @subscription.reload.current_period_ends_at
    assert_equal 2, AuditEvent.where(action: "agent_subscription.month_granted", auditable_id: @subscription.id).count
    assert_not_includes AuditEvent.where(auditable_id: @subscription.id).map(&:changeset).to_json, @workspace.owner.email
    @workspace.update!(status: "suspended")
    Agent::Subscriptions.grant_month!(workspace: @workspace, actor: operator)
    assert_equal "suspended", @workspace.reload.status
    assert_not Agent::Access.new(@workspace).commercial?
  end

  test "clients notes references archives and formula safe exports never cross workspaces" do
    other = agent_workspace
    other_client = other.agent_clients.create!(name: "OTRO CLIENTE", phone: "5491155559999")
    other_trip = agent_trip(workspace: other)
    login_agent(@workspace)
    get agent_client_path(other_client)
    assert_response :not_found
    patch agent_client_path(other_client), params: { agent_client: { name: "No" } }
    assert_response :not_found
    post agent_client_notes_path(other_client), params: { agent_client_note: { body: "No" } }
    assert_response :not_found
    post agent_client_notes_path(@client), params: { agent_client_note: { body: "No", agent_trip_id: other_trip.id } }
    assert_response :not_found
    assert_raises(ActiveRecord::RecordInvalid) { @client.notes.create!(agent_workspace: @workspace, body: "No", agent_trip: other_trip) }
    post agent_clients_path, params: { agent_client: { name: "=1+1", phone: "+54 9 11 1111 1111", agent_workspace_id: other.id } }
    created = @workspace.agent_clients.find(response.location.split("/").last)
    assert_equal "5491111111111", created.phone
    post agent_client_notes_path(created), params: { agent_client_note: { body: "+FORMULA", agent_trip_id: @trip.id, agent_workspace_id: other.id } }
    get export_agent_clients_path(format: :csv)
    assert_includes response.body, "'=1+1"
    assert_not_includes response.body, "OTRO CLIENTE"
    get export_agent_clients_path(format: :csv, notes: "1")
    assert_includes response.body, "'+FORMULA"
    assert_not_includes response.body, "OTRO CLIENTE"
    get agent_clients_path(q: "=1+1")
    assert_includes response.body, "=1+1"
    post archive_agent_client_path(created)
    assert created.reload.archived_at
    get agent_clients_path
    assert_not_includes response.body, "=1+1"
    get agent_clients_path(archived: "1")
    assert_includes response.body, "=1+1"
    assert_equal 1, created.notes.count
    assert_empty AuditEvent.where(auditable_type: %w[AgentClient AgentClientNote]).reject { |event| event.changeset.empty? }
  end
  test "client writes notes and searches redact personal content from SQL logs" do
    login_agent(@workspace)
    buffer = StringIO.new
    previous_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(buffer)
    post agent_clients_path, params: { agent_client: { name: "CONTACTO-SECRETO-UNICOTEST", phone: "5491166667777", email: "privado-unique@example.test" } }
    client = @workspace.agent_clients.find(response.location.split("/").last)
    post agent_client_notes_path(client), params: { agent_client_note: { body: "NOTA-SECRETA-UNICOTEST" } }
    get agent_clients_path, params: { q: "CONTACTO-SECRETO-UNICOTEST" }
    assert_response :success
    assert_includes response.body, "CONTACTO-SECRETO-UNICOTEST"
    get agent_suppliers_path, params: { q: "CONTACTO-SECRETO-UNICOTEST" }
    assert_response :success
    %w[CONTACTO-SECRETO-UNICOTEST NOTA-SECRETA-UNICOTEST privado-unique@example.test 5491166667777].each do |secret|
      assert_not_includes buffer.string, secret
    end
  ensure
    ActiveRecord::Base.logger = previous_logger if previous_logger
  end

  test "private agenda and exports require the owner on both platform and historical hosts" do
    host! PlatformHosts.platform_host
    [ agent_client_path(@client), export_agent_clients_path(format: :csv), agent_export_path(format: :json) ].each do |path|
      get path
      assert_response :redirect
      assert_not_includes response.body, @client.name
    end
    other = agent_workspace
    login_agent(other)
    get agent_client_path(@client)
    assert_response :not_found
    get agent_export_path(format: :json)
    assert_response :success
    assert_empty response.parsed_body["clients"]
    login_agent(@workspace)
    host! other.hostname
    # This host retains the other owner's independent session. A foreign ID
    # must still be inaccessible; cookies are deliberately not shared by hosts.
    get agent_client_path(@client)
    assert_response :not_found
    assert_not_includes response.body, @client.name
    host! PlatformHosts.platform_host
    get agent_client_path(@client)
    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Cache-Control"], "no-store"
    get agent_site_trip_path(agent_slug: @workspace.slug, slug: @trip.slug)
    assert_response :success
    assert_not_includes response.body, @client.name
    assert_not_includes response.body, @client.notes.sole.body
  end
  test "legacy hosts serve images and personal photos on the same origin and still enforce expiry" do
    workspace = agent_workspace(show_about: true)
    trip = agent_trip(workspace:, cover: png_upload)
    trip.publish!
    workspace.about_photo.attach(png_upload)
    host! workspace.hostname
    image_path = agent_public_image_path(slug: trip.slug, revision_id: trip.published_revision_id)
    photo_path = agent_public_about_photo_path(blob_id: workspace.about_photo.blob_id)
    get root_path
    assert_response :success
    assert_select "img[src=?]", PlatformHosts.url(host: workspace.hostname, path: image_path)
    assert_select "img[src=?]", PlatformHosts.url(host: workspace.hostname, path: photo_path)
    [ image_path, photo_path ].each { |path| get path; assert_response :success }
    workspace.agent_subscription.update!(trial_starts_at: 20.days.ago, trial_ends_at: 1.day.ago)
    [ root_path, image_path, photo_path ].each { |path| get path; assert_response :not_found }
  end
end
