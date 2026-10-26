require "test_helper"
require_relative "../support_agent_data"

class ResellerHardeningTest < ActionDispatch::IntegrationTest
  include AgentTestData

  setup do
    @workspace = agent_workspace
    login_agent(@workspace)
  end

  test "invalid money retains manual fields and private flyer until corrected publication" do
    attributes = { new_supplier_name: "Operador", title: "Mi flyer", destination: "Salta", departs_on: 2.months.from_now.to_date, price: "no sé", currency: "ARS", price_unit: "per_person", cover: png_upload }
    assert_no_difference "AgentTrip.count" do
      post agent_trips_path, params: { commit_action: "publish", agent_trip_revision: attributes }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    assert_select "input[name='agent_trip_revision[title]'][value='Mi flyer']"
    assert_select "input[name='agent_trip_revision[price]'][value='no sé']"
    token = css_select("input[name=retained_cover]").first["value"]
    assert_empty @workspace.agent_suppliers
    post agent_trips_path, params: { retained_cover: token, commit_action: "publish", agent_trip_revision: attributes.except(:cover).merge(price: "450.000,50") }
    assert_response :redirect
    trip = @workspace.agent_trips.last
    assert_equal "published", trip.status
    assert_equal 45_000_050, trip.current_revision.price_cents
    assert_equal File.binread(png_upload.path), trip.current_revision.cover.download
    other = agent_workspace
    login_agent(other)
    assert_no_difference "AgentTrip.count" do
      post agent_trips_path, params: { retained_cover: token, agent_trip_revision: { new_supplier_name: "Ataque" } }
    end
    assert_response :not_found
  end

  test "publication failure keeps uploaded flyer and stale edits keep their original version token" do
    attributes = { new_supplier_name: "Operador", title: "Datos incompletos", cover: png_upload }
    post agent_trips_path, params: { commit_action: "publish", agent_trip_revision: attributes }
    assert_response :unprocessable_entity
    assert_select "input[name=retained_cover]"
    assert_select "input[value='Datos incompletos']"
    trip = agent_trip(workspace: @workspace)
    old = trip.current_revision_id
    Agent::SaveTrip.call(workspace: @workspace, trip:, attributes: trip.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "Otra ventana"))
    patch agent_trip_path(trip), params: { expected_revision_id: old, agent_trip_revision: { title: "Mi corrección", agent_supplier_id: trip.current_revision.agent_supplier_id, price: "123abc" } }
    assert_response :unprocessable_entity
    assert_select "input[value='123abc']"
    patch agent_trip_path(trip), params: { expected_revision_id: old, agent_trip_revision: { title: "Mi corrección", agent_supplier_id: trip.current_revision.agent_supplier_id, price: "450000" } }
    assert_response :conflict
    assert_select "input[name=expected_revision_id][value='#{old}']"
    assert_select "input[value='Mi corrección']"
    assert_equal "Otra ventana", trip.reload.current_revision.title
  end

  test "import review survives invalid price and duplicate supplier then allows correction" do
    task = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload)
    item = task.items.create!(agent_workspace: @workspace, position: 0, extracted: gemini_trip)
    supplier = @workspace.agent_suppliers.create!(name: "Operador")
    raw = { title: "Mi corrección IA", destination: "Salta", price: "no sé", agent_supplier_id: supplier.id }
    patch agent_import_item_path(task, item), params: { commit_action: "publish", agent_trip_revision: raw }
    assert_response :unprocessable_entity
    assert_select "input[value='no sé']"
    assert_select "input[value='Mi corrección IA']"
    assert_equal "no sé", item.reload.review_data["price"]
    assert task.source.attached?
    patch agent_import_item_path(task, item), params: { commit_action: "create_supplier", new_supplier_name: "OPERADOR", agent_trip_revision: raw.merge(price: "450000") }
    assert_response :unprocessable_entity
    assert_select "input[value='Mi corrección IA']"
    patch agent_import_item_path(task, item), params: { commit_action: "draft", agent_trip_revision: raw.merge(price: "450000") }
    assert_response :redirect
    assert_equal task.source.blob_id, item.reload.agent_trip.current_revision.cover.blob_id
  end

  test "daily limit keeps uploaded source available for manual entry and search query editable" do
    previous_import = ENV["AGENT_IMPORTS_PER_DAY"]
    previous_search = ENV["AGENT_SEARCHES_PER_DAY"]
    ENV["AGENT_IMPORTS_PER_DAY"] = ENV["AGENT_SEARCHES_PER_DAY"] = "1"
    @workspace.agent_imports.create!(idempotency_key: "used")
    post agent_imports_path, params: { source: png_upload, idempotency_key: "retained" }
    assert_response :too_many_requests
    assert_select "[role=alert]", text: /límite diario/
    token = css_select("input[name=retained_cover]").first["value"]
    get new_agent_trip_path(retained_cover: token)
    assert_response :success
    assert_select "input[name=retained_cover]"
    post agent_trips_path, params: { retained_cover: token, agent_trip_revision: { new_supplier_name: "Manual" } }
    assert_response :redirect
    assert @workspace.agent_trips.last.current_revision.cover.attached?
    @workspace.agent_searches.create!(idempotency_key: "used", query: "antes")
    post agent_searches_path, params: { query: "Salta para enero", idempotency_key: "limited" }
    assert_response :too_many_requests
    assert_select "textarea[name=query]", text: "Salta para enero"
    assert_select "a[href='#{agent_trips_path}']"
  ensure
    previous_import ? ENV["AGENT_IMPORTS_PER_DAY"] = previous_import : ENV.delete("AGENT_IMPORTS_PER_DAY")
    previous_search ? ENV["AGENT_SEARCHES_PER_DAY"] = previous_search : ENV.delete("AGENT_SEARCHES_PER_DAY")
  end

  test "invalid source reopens import upload form with clear message" do
    file = Tempfile.new([ "bad", ".png" ])
    file.write("not an image"); file.close
    post agent_imports_path, params: { source: Rack::Test::UploadedFile.new(file.path, "image/png"), idempotency_key: "bad-file" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /archivo|imagen/
    assert_select "input[type=file]"
    assert_select "input[name=idempotency_key][value=bad-file]"
    assert_empty @workspace.agent_imports
  ensure
    file&.unlink
  end

  test "anonymous crawler sees only published revision and revoked images return no-store 404" do
    trip = agent_trip(workspace: @workspace, cover: png_upload)
    trip.publish!
    original = trip.published_revision
    Agent::SaveTrip.call(workspace: @workspace, trip:, attributes: original.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "PRIVATE REVISION"))
    private_revision = trip.reload.current_revision
    reset!
    host! @workspace.hostname
    get agent_public_trip_path(slug: trip.slug)
    assert_response :success
    assert_not_includes response.body, "PRIVATE REVISION"
    assert_select "meta[property='og:title'][content='#{original.title}']"
    canonical = css_select("link[rel=canonical]").first["href"]
    assert_equal @workspace.url(path: agent_public_trip_path(slug: trip.slug)), canonical
    image = css_select("meta[property='og:image']").first["content"]
    get URI(image).request_uri
    assert_response :success
    assert_equal File.binread(png_upload.path), response.body
    get agent_public_image_path(slug: trip.slug, revision_id: private_revision.id)
    assert_response :not_found
    trip.publish!
    get agent_public_image_path(slug: trip.slug, revision_id: original.id)
    assert_response :not_found
    get agent_public_trip_path(slug: trip.slug)
    assert_select "meta[property='og:title'][content='PRIVATE REVISION']"
    trip.update!(status: "unpublished")
    get agent_public_image_path(slug: trip.slug, revision_id: private_revision.id)
    assert_response :not_found
    assert_includes response.headers["Cache-Control"], "no-store"
  end
end
