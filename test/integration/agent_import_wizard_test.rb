require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentImportWizardTest < ActionDispatch::IntegrationTest
  include AgentTestData

  setup do
    travel_to Time.utc(2026, 11, 12, 15)
    @workspace = agent_workspace
    @supplier = @workspace.agent_suppliers.create!(name: "Carlos Sansot Viajes")
    @import = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload)
    @previous_key = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-api-key"
    departures = [ 2, 8, 11, 14, 17, 25 ].map do |day|
      # A model using next-future-occurrence guesses 2027 for the first dates.
      { label: "#{day} de noviembre", departs_on: "2027-11-#{day.to_s.rjust(2, '0')}", returns_on: nil }
    end
    @conditions = "Contado/efectivo: $105.000 base triple y cuádruple; $115.000 base doble. Lista: $131.250 y $143.750 respectivamente. Gastos administrativos adicionales: $15.000."
    stub_gemini(trips: [ gemini_trip(title: "Villa Carlos Paz", destination: "Villa Carlos Paz", supplier_name: "Carlos Sansot",
      departs_on: nil, departures:, duration_days: 5, duration_nights: 3, hotel: "Gran Victoria", meal_plan: "Media pensión",
      transport: "Bus semi cama", included_services: "Coordinador", price_cents: 10_500_000, price_basis: "Contado/efectivo, base triple y cuádruple", conditions: @conditions) ])
    AgentAiJob.perform_now("import", @import.id)
    login_agent(@workspace)
  end

  teardown do
    @previous_key ? ENV["GEMINI_API_KEY"] = @previous_key : ENV.delete("GEMINI_API_KEY")
  end

  def payload
    get agent_trip_import_path(@import, format: :json)
    assert_response :success
    response.parsed_body
  end

  def rows
    payload.fetch("items").map { |item| item.slice("id", "values", "selected", "overrides") }
  end

  test "the old import pages are removed and entry points open the trips wizard" do
    %w[/asesor/importaciones /asesor/importaciones/archivo /asesor/importaciones/archivo/elementos/ficha/editar].each do |path|
      get path
      assert_response :not_found
    end
    get agent_trips_path(import: true)
    assert_response :success
    assert_select "#main-sidebar a", text: "Importar", count: 0
    assert_select "[data-import-wizard-auto-open-value=true]"
    assert_select "[data-import-wizard-url-value=?]", agent_trip_imports_path(format: :json)
    assert_select "dialog[data-import-wizard-target=dialog]", count: 1
    get agent_root_path
    assert_select "a[href=?]", agent_trips_path(import: true), text: "Importar con IA"
    get new_agent_trip_path
    assert_select "a[href=?]", agent_trips_path(import: true), text: "Importar flyer con IA"
    get agent_trip_imports_path
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal [ @import.id ], response.parsed_body["imports"].pluck("id")
    assert_equal agent_trip_import_path(@import, format: :json), response.parsed_body["imports"].first["url"]
  end

  test "six Sansot departures create six independent drafts with original source and survive repeat confirmation" do
    assert_equal "completed", @import.reload.status
    data = payload
    expected = %w[2026-11-02 2026-11-08 2026-11-11 2026-11-14 2026-11-17 2026-11-25]
    assert_equal expected, data["items"].map { |item| item.dig("values", "departs_on") }
    assert data["items"].all? { |item| item.dig("values", "agent_supplier_id") == @supplier.id }
    assert_difference [ "AgentTrip.count", "AgentTripRevision.count" ], 6 do
      post confirm_agent_trip_import_path(@import), params: { items: rows }, as: :json
      assert_response :success
    end
    assert_equal 6, response.parsed_body["count"]
    assert_equal agent_trips_path(tab: "drafts"), response.parsed_body["redirect_url"]
    trips = @import.items.reload.map(&:agent_trip)
    assert_equal 6, trips.map(&:id).uniq.size
    assert_equal expected, trips.map { |trip| trip.current_revision.departs_on.iso8601 }
    trips.each do |trip|
      assert_equal "draft", trip.status
      assert_nil trip.published_revision
      revision = trip.current_revision
      assert_equal @workspace.id, revision.agent_workspace_id
      assert_equal @supplier.id, revision.agent_supplier_id
      assert_equal "Gran Victoria", revision.hotel
      assert_equal 5, revision.duration_days
      assert_equal 3, revision.duration_nights
      assert_equal "Media pensión", revision.meal_plan
      assert_equal "Bus semi cama", revision.transport
      assert_equal "Coordinador", revision.included_services
      assert_equal 10_500_000, revision.price_cents
      assert_equal @conditions, revision.conditions
      assert_equal @import.source.blob, revision.flyer_source.blob
      assert_equal @import.preview.blob, revision.cover.blob
    end
    assert_no_difference [ "AgentTrip.count", "AgentTripRevision.count" ] do
      post confirm_agent_trip_import_path(@import), params: { items: rows }, as: :json
      assert_response :success
      assert_equal 6, response.parsed_body["count"]
    end
    get agent_trips_path(tab: "drafts")
    assert_select "tbody tr", count: 6
    assert_select "#trip-tab-drafts[aria-selected=true]", text: /Borradores.*6/m
    assert_raises(ActiveRecord::RecordInvalid) { trips.first.publish! }
    assert_equal "draft", trips.first.reload.status
  end

  test "deselection shared edits individual corrections and resume use persisted review" do
    changes = rows
    changes.each { |row| row["values"]["hotel"] = "Hotel corregido" }
    changes.first["selected"] = false
    changes[1]["values"].merge!("title" => "Salida personalizada", "hotel" => "Hotel particular", "price" => "115000", "currency" => "USD")
    changes[1]["overrides"] = %w[title hotel price currency]
    patch review_agent_trip_import_path(@import), params: { items: changes }, as: :json
    assert_response :success
    data = payload["items"]
    assert_equal false, data.first["selected"]
    assert_equal "Hotel particular", data[1]["values"]["hotel"]
    assert_equal %w[title hotel price currency], data[1]["overrides"]
    assert_difference "AgentTrip.count", 5 do
      post confirm_agent_trip_import_path(@import), params: {}, as: :json
      assert_response :success
    end
    assert_nil @import.items.first.agent_trip_id
    revised = @import.items.second.agent_trip.current_revision
    assert_equal "Salida personalizada", revised.title
    assert_equal "Hotel particular", revised.hotel
    assert_equal 11_500_000, revised.price_cents
    assert_equal "USD", revised.currency
    assert_equal [ "Hotel corregido" ], @import.items.drop(2).map { |item| item.agent_trip.current_revision.hotel }.uniq
  end

  test "a failure rolls back every trip while keeping corrections for a retry without Gemini" do
    changes = rows
    changes.last["values"]["duration_days"] = "0"
    assert_no_difference [ "AgentTrip.count", "AgentTripRevision.count" ] do
      post confirm_agent_trip_import_path(@import), params: { items: changes }, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal "0", @import.items.last.review_data["duration_days"]
    assert_equal 0, @import.items.where.not(agent_trip_id: nil).count
    changes.last["values"]["duration_days"] = "5"
    assert_difference "AgentTrip.count", 6 do
      post confirm_agent_trip_import_path(@import), params: { items: changes }, as: :json
      assert_response :success
    end
    assert_requested :post, %r{https://generativelanguage.googleapis.com/}, times: 1
  end

  test "manual dates additions and repeated review requests are idempotent" do
    changes = rows
    changes.first["values"]["departs_on"] = "2028-12-02"
    additional = changes.first.except("id").merge("template_id" => changes.first["id"], "client_key" => "manual-date-1")
    additional["values"] = additional["values"].merge("departs_on" => "2026-12-20")
    changes << additional
    2.times do
      patch review_agent_trip_import_path(@import), params: { items: changes }, as: :json
      assert_response :success
    end
    assert_equal 7, @import.items.count
    assert_equal "2028-12-02", payload["items"].first["values"]["departs_on"]
    assert_difference "AgentTrip.count", 7 do
      post confirm_agent_trip_import_path(@import), params: {}, as: :json
      assert_response :success
    end
  end

  test "duplicate trips are disclosed require acknowledgement and never get overwritten" do
    existing = agent_trip(workspace: @workspace, supplier: @supplier, destination: "Villa Carlos Paz", departs_on: "2026-11-14", returns_on: nil)
    revision_id = existing.current_revision_id
    data = payload
    assert_equal existing.id, data["items"][3]["duplicates"].first["id"]
    assert_no_difference "AgentTrip.count" do
      post confirm_agent_trip_import_path(@import), params: { items: rows }, as: :json
      assert_response :unprocessable_entity
      assert_match(/duplicados/, response.parsed_body["error"])
    end
    assert_difference "AgentTrip.count", 6 do
      post confirm_agent_trip_import_path(@import), params: { acknowledge_duplicates: true }, as: :json
      assert_response :success
    end
    assert_equal revision_id, existing.reload.current_revision_id
  end

  test "normalized supplier creation reuses existing companies and ambiguous names stay unselected" do
    item = @import.items.first
    item.update!(extracted: item.extracted.merge("supplier_name" => "Carlos Sansot Viajes Leg. 12569"))
    assert_equal @supplier.id, payload["items"].first.dig("values", "agent_supplier_id")
    assert_no_difference "AgentSupplier.count" do
      post supplier_agent_trip_import_path(@import), params: { name: "  CÁRLOS   SANSÓT viajes Legajo N° 12569 " }, as: :json
      assert_response :success
      assert_equal @supplier.id, response.parsed_body["supplier"]["id"]
    end
    item.update!(extracted: item.extracted.merge("supplier_name" => "Carlos Sansot"))
    @workspace.agent_suppliers.create!(name: "Carlos Sansot Turismo")
    assert payload["items"].all? { |item| item.dig("values", "agent_supplier_id").nil? && item["supplier_candidates"].size == 2 }
    assert_no_difference "AgentSupplier.count" do
      post supplier_agent_trip_import_path(@import), params: { name: "Carlos Sansot" }, as: :json
      assert_response :unprocessable_entity
    end
    assert_difference "@workspace.agent_suppliers.count", 1 do
      post supplier_agent_trip_import_path(@import), params: { name: "Nueva Empresa" }, as: :json
      assert_response :success
    end
    assert_no_difference "AgentSupplier.count" do
      post supplier_agent_trip_import_path(@import), params: { name: "NUEVA ÉMPRESA" }, as: :json
      assert_response :success
    end
  end

  test "another workspace cannot supply items companies sources or imports" do
    other = agent_workspace
    foreign_supplier = other.agent_suppliers.create!(name: "Carlos Sansot Viajes")
    foreign_import = other.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload)
    foreign_item = foreign_import.items.create!(agent_workspace: other, position: 0)
    changes = rows
    changes.first["values"]["agent_supplier_id"] = foreign_supplier.id
    assert_no_difference "AgentTrip.count" do
      post confirm_agent_trip_import_path(@import), params: { items: changes }, as: :json
      assert_response :not_found
    end
    changes = rows
    changes.first["id"] = foreign_item.id
    patch review_agent_trip_import_path(@import), params: { items: changes }, as: :json
    assert_response :not_found
    [ agent_trip_import_path(foreign_import, format: :json), source_agent_trip_import_path(foreign_import) ].each do |path|
      get path
      assert_response :not_found
    end
    post confirm_agent_trip_import_path(foreign_import), params: {}, as: :json
    assert_response :not_found
    assert_equal 0, other.agent_trips.count
  end

  test "upload uses current async infrastructure and a repeated request does not create another import" do
    key = SecureRandom.uuid
    assert_difference "AgentImport.count", 1 do
      assert_enqueued_with(job: AgentAiJob) do
        post agent_trip_imports_path(format: :json), params: { source: png_upload, idempotency_key: key }
        assert_response :success
        assert_equal "pending", response.parsed_body["status"]
      end
    end
    id = response.parsed_body["id"]
    assert_no_difference "AgentImport.count" do
      post agent_trip_imports_path(format: :json), params: { source: png_upload, idempotency_key: key }
      assert_response :success
      assert_equal id, response.parsed_body["id"]
    end
  end

  test "upload validation and AI quota failures return actionable JSON and retain valid files" do
    post agent_trip_imports_path(format: :json), params: { idempotency_key: SecureRandom.uuid }
    assert_response :unprocessable_entity
    assert_match(/archivo/, response.parsed_body["error"])
    previous_limit = ENV["AGENT_PRO_MONTHLY_AI_UNITS"]
    ENV["AGENT_PRO_MONTHLY_AI_UNITS"] = "1"
    assert_no_difference "AgentImport.count" do
      post agent_trip_imports_path(format: :json), params: { source: png_upload, idempotency_key: SecureRandom.uuid }
      assert_response :too_many_requests
      assert_match(/presupuesto mensual/, response.parsed_body["error"])
      assert response.parsed_body["retained_cover"].present?
    end
  ensure
    previous_limit ? ENV["AGENT_PRO_MONTHLY_AI_UNITS"] = previous_limit : ENV.delete("AGENT_PRO_MONTHLY_AI_UNITS")
  end

  test "different programs keep their own organizer and shared attributes" do
    other_supplier = @workspace.agent_suppliers.create!(name: "Operador del Sur")
    @import.items.create!(agent_workspace: @workspace, position: 6, extracted: { "program_key" => "1", "supplier_name" => "Operador del Sur",
      "title" => "Bariloche", "destination" => "Bariloche", "departs_on" => "2026-12-20", "hotel" => "Hotel del Sur" })
    data = payload["items"]
    assert_equal 2, data.pluck("program").uniq.size
    assert_equal @supplier.id, data.first.dig("values", "agent_supplier_id")
    assert_equal other_supplier.id, data.last.dig("values", "agent_supplier_id")
    assert_difference "AgentTrip.count", 7 do
      post confirm_agent_trip_import_path(@import), params: { items: rows }, as: :json
      assert_response :success
    end
    revision = @import.items.last.agent_trip.current_revision
    assert_equal other_supplier, revision.agent_supplier
    assert_equal "Hotel del Sur", revision.hotel
    assert_equal "Bariloche", revision.destination
  end
end
