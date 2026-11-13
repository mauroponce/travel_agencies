require "test_helper"
require_relative "../support_agent_data"

class AgentTripListTest < ActionDispatch::IntegrationTest
  include AgentTestData

  setup do
    @workspace = agent_workspace
    @supplier = @workspace.agent_suppliers.create!(name: "Cóndor Turismo")
    login_agent(@workspace)
  end

  test "entry shows exactly three tabs defaults to published and renders current revisions" do
    published = agent_trip(workspace: @workspace, supplier: @supplier, title: "Título público")
    published.publish!
    original = published.published_revision_id
    Agent::SaveTrip.call(workspace: @workspace, trip: published, expected_revision_id: published.current_revision_id,
      attributes: published.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "Título interno"))
    draft = agent_trip(workspace: @workspace)
    draft.update!(status: "unpublished")
    get agent_trips_path
    assert_response :success
    assert_select "a[role=tab]", count: 3
    assert_select "a[role=tab][aria-selected=true][data-tab=published]", count: 1
    assert_equal [ published.id ], row_ids
    assert_select "tbody", text: /Título interno/
    assert_select "tbody", text: /Cambios sin publicar/
    assert_select "select[name=status], select[name=sort]", count: 0
    assert_select "a[data-tab=drafts] .agent-trip-tab-count", text: "1"
    assert_equal original, published.reload.published_revision_id
    get agent_trips_path(tab: "all", status: "unpublished")
    assert_equal [ published.id ], row_ids
  end

  test "incomplete draft and unpublished rows share one label without invented commercial values" do
    first = Agent::SaveTrip.call(workspace: @workspace, attributes: { "agent_supplier_id" => @supplier.id })
    second = agent_trip(workspace: @workspace, supplier: @supplier, price_unit: "per_group", duration_nights: 0)
    second.update!(status: "unpublished")
    archived = agent_trip(workspace: @workspace)
    archived.update!(status: "archived")
    get agent_trips_path(tab: "drafts")
    assert_equal [ second.id, first.id ], row_ids
    assert_select ".agent-trip-state", text: "Borrador", count: 2
    assert_select "tbody", text: /Sin definir/
    assert_select "tbody", text: /Por grupo/
    assert_select "tbody", text: /0 noches/
    assert_not_includes response.body, "Despublicado"
    get agent_trips_path(tab: "archived")
    assert_equal [ archived.id ], row_ids
    assert_select ".agent-trip-state", text: "Archivado", count: 1
  end

  test "pagination shows twenty records preserves filters and clamps an out of range page" do
    21.times { agent_trip(workspace: @workspace, supplier: @supplier, destination: "Mendoza", currency: "USD").publish! }
    agent_trip(workspace: @workspace, supplier: @supplier, destination: "Mendoza", currency: "USD")
    agent_trip(workspace: agent_workspace, destination: "Mendoza", currency: "USD").publish!
    filters = { q: "mendoza", supplier_id: @supplier.id.to_s, currency: "USD", from: Date.current.iso8601, to: 1.year.from_now.to_date.iso8601 }
    get agent_trips_path, params: filters
    assert_response :success
    assert_equal 20, row_ids.size
    assert_select ".agent-trip-tab-count", text: "21", count: 1
    assert_select ".agent-trip-pagination", text: /Mostrando 1–20 de 21 viajes/
    assert_select ".agent-trip-pagination", text: /20 por página/
    next_link = css_select("a[rel=next]").first
    preserved = Rack::Utils.parse_nested_query(URI(next_link["href"]).query)
    assert_equal filters.stringify_keys.merge("tab" => "published", "page" => "2"), preserved.stringify_keys
    get next_link["href"]
    assert_equal 1, row_ids.size
    assert_select ".agent-trip-pagination", text: /Mostrando 21–21 de 21 viajes/
    assert_select "form.agent-trip-filters input[name=page]", count: 0
    assert_select "a[data-tab=drafts]" do |links|
      assert_nil Rack::Utils.parse_nested_query(URI(links.first["href"]).query)["page"]
    end
    get agent_trips_path, params: filters.merge(page: 999)
    assert_equal 1, row_ids.size
    assert_select "[aria-current=page]", text: "2"
  end

  test "list actions preserve context update groups and clamp the page after removing its last row" do
    21.times { agent_trip(workspace: @workspace, supplier: @supplier).publish! }
    get agent_trips_path(page: 2)
    last_id = row_ids.fetch(0)
    post unpublish_agent_trip_path(last_id), params: { list: { tab: "published", page: 2 } }
    assert_redirected_to agent_trips_path(tab: "published", page: "2")
    follow_redirect!
    assert_response :success
    assert_equal 20, row_ids.size
    assert_select ".agent-trip-pagination", text: /Mostrando 1–20 de 20 viajes/
    assert_select "a[data-tab=drafts] .agent-trip-tab-count", text: "1"
    assert_includes response.body, "Viaje despublicado."
    post archive_agent_trip_path(last_id), params: { list: { tab: "drafts", q: "cordoba" } }
    follow_redirect!
    assert_select "a[data-tab=archived] .agent-trip-tab-count", text: "1"
    assert_select "a[data-tab=drafts] .agent-trip-tab-count", text: "0"
    assert_select ".agent-trip-empty", text: /No encontramos viajes/
  end

  test "publication errors return to the filtered list and archived trips can be republished" do
    invalid = Agent::SaveTrip.call(workspace: @workspace, attributes: { "agent_supplier_id" => @supplier.id })
    post publish_agent_trip_path(invalid), params: { list: { tab: "drafts", supplier_id: @supplier.id } }
    assert_redirected_to agent_trips_path(tab: "drafts", supplier_id: @supplier.id)
    follow_redirect!
    assert_includes response.body, "es obligatorio para publicar"
    assert_equal "draft", invalid.reload.status
    archived = agent_trip(workspace: @workspace, supplier: @supplier)
    archived.update!(status: "archived")
    post publish_agent_trip_path(archived), params: { list: { tab: "archived" } }
    follow_redirect!
    assert_equal "published", archived.reload.status
    assert_select "a[data-tab=published] .agent-trip-tab-count", text: "1"
  end

  test "public actions use published revision visibility while labels use persisted state" do
    trip = agent_trip(workspace: @workspace, supplier: @supplier)
    trip.publish!
    paused = @workspace.agent_suppliers.create!(name: "Pausado")
    Agent::SaveTrip.call(workspace: @workspace, trip:, expected_revision_id: trip.current_revision_id,
      attributes: trip.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("agent_supplier_id" => paused.id))
    paused.update!(status: "paused")
    get agent_trips_path
    assert_select "a[role=menuitem]", text: "Ver ficha pública", count: 1
    assert_select "button[role=menuitem]", text: "Copiar enlace", count: 1
    assert_select "button[role=menuitem]", text: "Publicar cambios", count: 1
    @supplier.update!(status: "paused")
    get agent_trips_path
    assert_equal [ trip.id ], row_ids
    assert_select ".agent-trip-state", text: "Publicado"
    assert_select "a[role=menuitem]", text: "Ver ficha pública", count: 0
    assert_select "button[role=menuitem]", text: "Copiar enlace", count: 0
  end

  test "expired access keeps read only rows and blocks writes on the server" do
    trip = agent_trip(workspace: @workspace)
    trip.publish!
    @workspace.agent_subscription.update!(trial_starts_at: 30.days.ago, trial_ends_at: 16.days.ago)
    get agent_trips_path
    assert_response :success
    assert_equal [ trip.id ], row_ids
    assert_select "a[role=menuitem]", text: "Ver detalle", count: 1
    assert_select "a[role=menuitem]", text: "Editar viaje", count: 0
    assert_select "button[role=menuitem]", count: 0
    post archive_agent_trip_path(trip), params: { list: { tab: "published" } }
    assert_response :forbidden
    assert_equal "published", trip.reload.status
  end

  test "foreign records and suppliers cannot leak through counts filters or actions" do
    other = agent_workspace
    foreign = agent_trip(workspace: other)
    foreign.publish!
    get agent_trips_path
    assert_empty row_ids
    assert_select ".agent-trip-tab-count", text: "0", count: 3
    assert_select "select[name=supplier_id] option[value=?]", foreign.current_revision.agent_supplier_id, count: 0
    %i[publish unpublish archive].each do |action|
      post public_send("#{action}_agent_trip_path", foreign), params: { list: { tab: "published" } }
      assert_response :not_found
    end
  end

  private

  def row_ids
    css_select("tbody tr[data-trip-id]").map { |row| row["data-trip-id"] }
  end
end
