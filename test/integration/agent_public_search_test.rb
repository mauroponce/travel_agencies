require "test_helper"
require_relative "../support_agent_data"

class AgentPublicSearchTest < ActionDispatch::IntegrationTest
  include AgentTestData

  test "autocomplete finds live published destinations without accents on both public URLs" do
    workspace = agent_workspace
    trip = agent_trip(workspace:, cover: png_upload)
    trip.publish!
    # A later private revision must never be used by public search.
    Agent::SaveTrip.call(workspace:, trip:, expected_revision_id: trip.current_revision_id,
      attributes: trip.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "BORRADOR SECRETO", "destination" => "Mendoza"))

    [ [ PlatformHosts.platform_host, agent_site_search_path(agent_slug: workspace.slug) ],
      [ workspace.hostname, agent_public_search_path ] ].each do |hostname, path|
      host! hostname
      get path, params: { q: "Cor" }
      assert_response :success
      assert_includes response.headers["Cache-Control"], "no-store"
      result = response.parsed_body.fetch("results").sole
      assert_equal "Córdoba en verano", result.fetch("title")
      assert_equal "Córdoba", result.fetch("destination")
      assert_equal trip.published_revision.departs_on.strftime("%d/%m/%Y"), result.fetch("date")
      assert_includes result.fetch("price"), "500.000"
      assert_equal workspace.url(path: agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)), result.fetch("url")
      image_path = agent_site_image_path(agent_slug: workspace.slug, slug: trip.slug, revision_id: trip.published_revision_id)
      assert_equal workspace.url(path: image_path), result.fetch("image_url")
      assert_equal %w[date destination image_url price title url], result.keys.sort
      host! PlatformHosts.platform_host
      get image_path
      assert_response :success
      assert_equal "image/png", response.media_type
      host! hostname
      get path, params: { q: "mendoza" }
      assert_empty response.parsed_body.fetch("results")
    end
  end

  test "autocomplete excludes past private inactive and foreign trips including with forged filters" do
    workspace = agent_workspace
    live = agent_trip(workspace:, departs_on: Date.current)
    live.publish!
    travel_to 1.day.ago do
      agent_trip(workspace:, title: "Córdoba pasada", departs_on: Date.current).publish!
    end
    unpublished = agent_trip(workspace:)
    unpublished.publish!
    unpublished.update!(status: "unpublished")
    archived = agent_trip(workspace:)
    archived.publish!
    archived.update!(status: "archived")
    agent_trip(workspace:, title: "Córdoba borrador")
    paused_supplier = workspace.agent_suppliers.create!(name: "Empresa pausada")
    paused = agent_trip(workspace:, supplier: paused_supplier)
    paused.publish!
    paused_supplier.update!(status: "paused")
    foreign = agent_trip(workspace: agent_workspace)
    foreign.publish!

    host! workspace.hostname
    get agent_public_search_path, params: { q: "Cor", status: "draft", supplier_id: foreign.current_revision.agent_supplier_id }
    assert_response :success
    assert_equal 1, response.parsed_body.fetch("results").size
    assert_nil response.parsed_body.fetch("results").sole.fetch("image_url")
    assert_includes response.parsed_body.fetch("results").map { |result| result.fetch("url") }, workspace.url(path: agent_site_trip_path(agent_slug: workspace.slug, slug: live.slug))
  end

  test "autocomplete requires two characters escapes wildcards and limits suggestions" do
    workspace = agent_workspace
    8.times { |i| agent_trip(workspace:, title: "Córdoba #{i}").publish! }
    host! PlatformHosts.platform_host
    path = agent_site_search_path(agent_slug: workspace.slug)
    [ nil, "", " ", "C", "%_" ].each do |q|
      get path, params: { q: }
      assert_response :success
      assert_empty response.parsed_body.fetch("results")
    end
    get path, params: { q: "  cOr  " }
    assert_equal 6, response.parsed_body.fetch("results").size
    expected = workspace.agent_trips.order(:id).limit(6).map { |trip| trip.published_revision.title }
    assert_equal expected, response.parsed_body.fetch("results").map { |result| result.fetch("title") }
  end

  test "search follows catalog visibility and workspace status" do
    workspace = agent_workspace(show_catalog: false)
    host! PlatformHosts.platform_host
    path = agent_site_search_path(agent_slug: workspace.slug)
    get path, params: { q: "Cor" }
    assert_response :not_found
    get agent_site_path(agent_slug: workspace.slug)
    assert_select ".agent-public-search", count: 0
    workspace.update!(show_catalog: true, status: "suspended")
    get path, params: { q: "Cor" }
    assert_response :not_found
  end

  test "top search filters public cards and works in the private website preview" do
    workspace = agent_workspace(show_about: true)
    agent_trip(workspace:).publish!
    agent_trip(workspace:, title: "Mendoza especial", destination: "Mendoza").publish!
    host! PlatformHosts.platform_host
    get agent_site_path(agent_slug: workspace.slug), params: { q: "Cor" }
    assert_response :success
    assert_select "main > section:first-child.agent-public-search"
    assert_select "input[role=combobox][value=Cor]"
    assert_select ".agent-trip-card h2", text: "Córdoba en verano"
    assert_select ".agent-trip-card h2", text: "Mendoza especial", count: 0
    get "/test/sign-in", params: { email: workspace.owner.email }
    get preview_agent_website_path
    assert_response :success
    assert_select ".agent-search-form[action=?]", preview_agent_website_path
    assert_select "[data-agent-catalog-search-url-value=?]", agent_site_search_path(agent_slug: workspace.slug)
  end

  test "only the owner sees inactive past and draft trips on their public page and preview stays public" do
    workspace = agent_workspace
    other = agent_workspace
    agent_trip(workspace:, title: "Propuesta vigente").publish!
    agent_trip(workspace:, title: "Propuesta en borrador")
    unpublished = agent_trip(workspace:, title: "Propuesta despublicada")
    unpublished.publish!
    unpublished.update!(status: "unpublished")
    archived = agent_trip(workspace:, title: "Propuesta archivada")
    archived.publish!
    archived.update!(status: "archived")
    travel_to 1.day.ago do
      agent_trip(workspace:, title: "Propuesta pasada", departs_on: Date.current).publish!
    end
    supplier = workspace.agent_suppliers.create!(name: "Proveedor inactivo")
    agent_trip(workspace:, supplier:, title: "Propuesta de empresa pausada").publish!
    supplier.update!(status: "paused")
    private_titles = [ "Propuesta en borrador", "Propuesta despublicada", "Propuesta archivada", "Propuesta pasada", "Propuesta de empresa pausada" ]

    [ [ PlatformHosts.platform_host, agent_site_path(agent_slug: workspace.slug) ],
      [ workspace.hostname, agent_public_catalog_path ] ].each do |hostname, path|
      host! hostname
      get path
      assert_response :success
      assert_select ".agent-trip-card h2", text: "Propuesta vigente"
      private_titles.each { |title| assert_select ".agent-trip-card h2", text: title, count: 0 }
      get "/test/sign-in", params: { email: workspace.owner.email }
      get path
      assert_response :success
      private_titles.each { |title| assert_select ".agent-trip-card h2", text: title }
      assert_select ".agent-badge", text: "Vencido"
      assert_select ".agent-badge", text: "Empresa pausada"
      assert_select ".agent-alert", text: /Vista de agente/
      assert_includes response.headers["Cache-Control"], "no-store"
      get path, params: { status: "unpublished" }
      assert_select ".agent-trip-card", count: 1
      assert_select ".agent-trip-card h2", text: "Propuesta despublicada"
      get preview_agent_website_path
      assert_response :success
      private_titles.each { |title| assert_select ".agent-trip-card h2", text: title, count: 0 }
      delete session_path
    end
    host! PlatformHosts.platform_host
    get "/test/sign-in", params: { email: other.owner.email }
    get agent_site_path(agent_slug: workspace.slug)
    assert_response :success
    private_titles.each { |title| assert_select ".agent-trip-card h2", text: title, count: 0 }
  end

  test "an unclaimed invitation does not grant anonymous visitors the owner view" do
    workspace = agent_workspace(owner: nil, invited_email: "invited@example.test")
    agent_trip(workspace:, title: "Borrador de una cuenta invitada")
    host! PlatformHosts.platform_host
    get agent_site_path(agent_slug: workspace.slug)
    assert_response :success
    assert_select ".agent-alert", text: /Vista de agente/, count: 0
    assert_select ".agent-trip-card", count: 0
  end
end
