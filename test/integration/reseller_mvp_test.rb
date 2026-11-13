require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class ResellerMvpTest < ActionDispatch::IntegrationTest
  include AgentTestData
  include ActiveJob::TestHelper

  setup do
    @workspace = agent_workspace
    login_agent(@workspace)
    clear_enqueued_jobs
  end

  test "inline provider manual publication preserves exact image bytes and stable URL through edits" do
    post agent_trips_path, params: { commit_action: "publish", agent_trip_revision: {
      new_supplier_name: "Carlos Sansot Viajes", destination: "Bariloche", departs_on: 2.months.from_now.to_date,
      price: "1.250.000,50", currency: "ARS", price_unit: "per_person", cover: png_upload, description: "Disfrutá la Patagonia"
    } }
    assert_response :redirect
    trip = @workspace.agent_trips.last
    assert_equal "Bariloche", trip.current_revision.title
    assert_equal 125_000_050, trip.current_revision.price_cents
    assert_equal trip.current_revision.flyer_source.blob_id, trip.current_revision.cover.blob_id
    bytes = File.binread(Rails.root.join("test/fixtures/files/agent.png"))
    slug = trip.slug
    revision = trip.published_revision
    get agent_trip_path(trip)
    assert_select "button", text: "Compartir flyer en WhatsApp"
    assert_select "button", text: "Copiar enlace"
    assert_select "button", text: "Copiar texto para estado"
    get cover_agent_trip_path(trip, revision_id: revision.id, download: true)
    assert_equal bytes, response.body
    assert_match "attachment", response.headers["Content-Disposition"]
    patch agent_trip_path(trip), params: { expected_revision_id: trip.current_revision_id, commit_action: "publish", agent_trip_revision: revision.attributes.slice(*AgentTripRevision::FIELDS).merge("price" => "1300000", "title" => "Bariloche editado") }
    assert_response :redirect
    assert_equal slug, trip.reload.slug
    assert_equal bytes, trip.current_revision.cover.download
    reset!
    host! @workspace.hostname
    get agent_public_trip_path(slug:)
    assert_response :success
    assert_select "meta[property='og:image']"
    assert_select "meta[name='description']"
    assert_select "a[href^='https://wa.me/']" do |links|
      contact = URI.decode_www_form(URI(links.first["href"]).query).to_h.fetch("text")
      assert_includes contact, "/viajes/#{slug}"
      assert_includes contact, "Bariloche editado"
    end
    get agent_public_image_path(slug:, revision_id: revision.id)
    assert_response :not_found
    get agent_public_image_path(slug:, revision_id: trip.published_revision_id)
    assert_response :success
    assert_equal bytes, response.body
    get source_agent_trip_path(trip)
    assert_redirected_to root_path
    login_agent(@workspace)
    post unpublish_agent_trip_path(trip)
    get agent_public_trip_path(slug:)
    assert_response :not_found
    get agent_public_image_path(slug:, revision_id: trip.published_revision_id)
    assert_response :not_found
  end

  test "imported flyer is retained on human confirmation and PDF gets first page JPEG" do
    task = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload, status: "completed")
    item = task.items.create!(agent_workspace: @workspace, position: 0, extracted: gemini_trip(evidence: {}))
    supplier = @workspace.agent_suppliers.create!(name: "Operador")
    post confirm_agent_trip_import_path(task), params: { items: [ { id: item.id, selected: true,
      values: { agent_supplier_id: supplier.id, price: "500000" } } ] }, as: :json
    assert_response :success
    trip = item.reload.agent_trip
    assert_equal task.source.blob_id, trip.current_revision.cover.blob_id
    assert_equal task.source.blob_id, trip.current_revision.flyer_source.blob_id
    task2 = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid)
    pdf = Prawn::Document.new { text "Primera pagina"; start_new_page; text "Segunda pagina" }.render
    task2.source.attach(io: StringIO.new(pdf), filename: "received.pdf", content_type: "application/pdf")
    trip2 = Agent::SaveTrip.call(workspace: @workspace, source_import: task2, attributes: { "agent_supplier_id" => supplier.id })
    assert_equal pdf, trip2.current_revision.flyer_source.download
    assert_equal "image/jpeg", trip2.current_revision.cover.content_type
    assert trip2.current_revision.cover.download.start_with?("\xFF\xD8\xFF".b)
    get preview_agent_trip_import_path(task2)
    assert_response :success
    get source_agent_trip_path(trip2)
    assert_equal pdf, response.body
  end

  test "manual fallback keeps source and tenants cannot mutate trips or read other flyers" do
    failed = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload, status: "error", error_code: "configuration")
    get agent_trip_import_path(failed)
    assert_equal "error", response.parsed_body["status"]
    get agent_trips_path(import_id: failed.id)
    assert_select "[data-import-wizard-resume-value=?]", failed.id
    post agent_trips_path, params: { source_import_id: failed.id, agent_trip_revision: { new_supplier_name: "Proveedor", title: "Mi borrador" } }
    assert_response :redirect
    trip = @workspace.agent_trips.last
    assert_equal failed.source.blob_id, trip.current_revision.cover.blob_id
    other = agent_workspace
    login_agent(other)
    get cover_agent_trip_path(trip)
    assert_response :not_found
    get source_agent_trip_path(trip)
    assert_response :not_found
    patch agent_trip_path(trip), params: { expected_revision_id: trip.current_revision_id, agent_trip_revision: { title: "Intrusión" } }
    assert_response :not_found
    post publish_agent_trip_path(trip)
    assert_response :not_found
    get new_agent_trip_path(source_import_id: failed.id)
    assert_response :not_found
    reset!
    host! @workspace.hostname
    post agent_trips_path, params: { agent_trip_revision: { title: "Sin sesión" } }
    assert_redirected_to root_path
  end

  test "public filters and colliding slugs are isolated and notes never leak" do
    trip = agent_trip(workspace: @workspace, title: "Oferta visible")
    trip.publish!
    foreign = agent_trip(workspace: agent_workspace, title: "FOREIGN PRIVATE")
    foreign.update_columns(slug: trip.slug)
    foreign.publish!
    trip.current_revision.agent_supplier.update!(notes: "NOTA SECRETA")
    host! @workspace.hostname
    get agent_public_trip_path(slug: trip.slug)
    assert_includes response.body, "Oferta visible"
    assert_not_includes response.body, "FOREIGN PRIVATE"
    assert_not_includes response.body, "NOTA SECRETA"
    get root_path, params: { supplier_id: foreign.current_revision.agent_supplier_id }
    assert_not_includes response.body, "Oferta visible"
    get root_path, params: { destination: "Córdoba", from: Date.current, to: 1.year.from_now.to_date, supplier_id: trip.current_revision.agent_supplier_id, currency: "ARS", price_unit: "per_person", max_price: "600000" }
    assert_includes response.body, "Oferta visible"
    get root_path, params: { currency: "ARS", price_unit: "per_person", max_price: "100" }
    assert_not_includes response.body, "Oferta visible"
  end

  test "failed publication keeps the correct revision token so corrections can be saved" do
    trip = agent_trip(workspace: @workspace)
    original_revision = trip.current_revision_id
    attributes = trip.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("price" => "500000", "departs_on" => "")
    patch agent_trip_path(trip), params: { expected_revision_id: original_revision, commit_action: "publish", agent_trip_revision: attributes }
    assert_response :unprocessable_entity
    assert_select "input[name='expected_revision_id'][value='#{original_revision}']"
    assert_equal original_revision, trip.reload.current_revision_id
    attributes["departs_on"] = 2.months.from_now.to_date
    patch agent_trip_path(trip), params: { expected_revision_id: original_revision, commit_action: "publish", agent_trip_revision: attributes }
    assert_response :redirect
    assert_equal "published", trip.reload.status
  end

  test "provider omission and duplicate names return useful errors without creating partial trips" do
    assert_no_difference "AgentTrip.count" do
      post agent_trips_path, params: { agent_trip_revision: { title: "Conservar mi título" } }
    end
    assert_response :unprocessable_entity
    assert_select "input[value='Conservar mi título']"
    supplier = @workspace.agent_suppliers.create!(name: "Operador")
    post agent_trips_path, params: { agent_trip_revision: { new_supplier_name: "OPERADOR", title: "Sin duplicar" } }
    assert_response :unprocessable_entity
    assert_equal 1, @workspace.agent_suppliers.count
    delete agent_supplier_path(supplier)
    assert_response :redirect
    assert_not AgentSupplier.exists?(supplier.id)
    used = agent_trip(workspace: @workspace).current_revision.agent_supplier
    delete agent_supplier_path(used)
    assert AgentSupplier.exists?(used.id)
  end

  test "uploads reject executable disguised as image without persisting a trip" do
    file = Tempfile.new([ "attack", ".png" ])
    file.write("<script>alert(1)</script>")
    file.close
    upload = Rack::Test::UploadedFile.new(file.path, "image/png")
    assert_no_difference "AgentTrip.count" do
      post agent_trips_path, params: { agent_trip_revision: { new_supplier_name: "Operador", cover: upload } }
    end
    assert_response :unprocessable_entity
    assert_empty @workspace.agent_suppliers
  ensure
    file&.unlink
  end
end
