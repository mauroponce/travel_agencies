require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"
require_relative "../support/agent_flyer_examples"

class AgentFaresTest < ActionDispatch::IntegrationTest
  include AgentTestData

  setup do
    travel_to Time.utc(2026, 11, 12, 15)
    @workspace = agent_workspace
    @supplier = @workspace.agent_suppliers.create!(name: "Operadora universal")
    login_agent(@workspace)
  end

  def import_programs(programs)
    # Swapping the organizer proves interpretation depends on the content.
    programs.each { |program| program["supplier_name"] = @supplier.name }
    data = Agent::AiContract.parse("import", { trips: programs }.to_json, today: Date.new(2026, 11, 12))
    task = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, status: "completed", source: png_upload)
    data["trips"].each_with_index { |extracted, position| task.items.create!(agent_workspace: @workspace, position:, extracted:) }
    task
  end

  def review_rows(task)
    get agent_trip_import_path(task, format: :json)
    assert_response :success
    response.parsed_body["items"].map { |item| item.slice("id", "values", "selected", "overrides") }
  end

  test "two bases remain editable tariffs on each of six independent trips" do
    task = import_programs(AgentFlyerExamples.multiple_bases)
    rows = review_rows(task)
    assert_equal 6, rows.size
    assert_equal [ "Base triple / cuádruple", "Base doble" ], rows.first["values"]["fares"].pluck("label")
    assert_equal [ "105000.00", "115000.00" ], rows.first["values"]["fares"].pluck("price")
    assert_equal [ "131250.00", "143750.00" ], rows.first["values"]["fares"].pluck("list_price")
    assert_equal [ "ARS" ], rows.flat_map { |row| row["values"]["fares"].pluck("currency") }.uniq
    rows.each { |row| row["values"]["fares"][1]["price"] = "116000" }
    rows.first["values"]["fares"][1]["price"] = "117000"
    rows.first["overrides"] = [ "fares" ]
    patch review_agent_trip_import_path(task), params: { items: rows }, as: :json
    assert_response :success
    assert_equal "117000", review_rows(task).first["values"]["fares"][1]["price"]
    assert_difference "AgentTrip.count", 6 do
      post confirm_agent_trip_import_path(task), params: {}, as: :json
      assert_response :success
    end
    revisions = task.items.reload.map(&:agent_trip_revision)
    assert revisions.all? { |revision| revision.fares.size == 2 && revision.region.nil? && revision.price_cents == 10_500_000 }
    assert_equal 11_700_000, revisions.first.fares.last["price_cents"]
    assert_equal [ 11_600_000 ], revisions.drop(1).map { |revision| revision.fares.last["price_cents"] }.uniq
    assert revisions.all? { |revision| revision.fares.first["list_price_cents"] == 13_125_000 && revision.conditions.include?("$15.000") }
    get agent_trip_path(task.items.first.agent_trip)
    assert_select "[role=tablist][aria-label='Tipos de tarifa'] [role=tab]", count: 2
    assert_select "[role=tabpanel]", text: /117.000,00/
    get edit_agent_trip_path(task.items.first.agent_trip)
    assert_select "input[name='agent_trip_revision[fares][][price]'][value='117000.00']"
  end

  test "a multi destination flyer preserves seven programs twelve dates and hotel alternatives" do
    programs = AgentFlyerExamples.multiple_programs
    programs[3]["departures"] = [ { "label" => "22-27 de febrero y 11 de marzo", "departs_on" => nil, "returns_on" => nil } ]
    programs[6]["departures"] = [ { "label" => "7-14 de marzo y 11-18 de abril", "departs_on" => nil, "returns_on" => nil } ]
    task = import_programs(programs)
    rows = review_rows(task)
    assert_equal 12, rows.size
    assert_equal 7, task.items.map { |item| item.extracted["program_key"] }.uniq.size
    assert rows.all? { |row| row["values"]["fares"].all? { |fare| fare["label"] == "Base doble" && fare["currency"] == "ARS" } }
    mina = rows.find { |row| row["values"]["destination"] == "Mina Clavero" }
    assert_equal "2027-02-21", mina["values"]["departs_on"]
    assert_equal "11999.00", mina["values"]["fares"].first["price"]
    carlos = rows.find { |row| row["values"]["destination"] == "Carlos Paz" }
    assert_equal [ "Hotel Grand Prix", "Hotel Sierrasol" ], carlos["values"]["fares"].pluck("hotel")
    assert_equal [ "14999.00", "12999.00" ], carlos["values"]["fares"].pluck("price")
    perlas = rows.find { |row| row["values"]["title"].start_with?("Perlas") }
    assert_nil perlas["values"]["departs_on"]
    perlas["values"]["departs_on"] = "2027-03-20"
    assert rows.none? { |row| row["values"]["departs_on"]&.include?("01-31") }
    assert_difference "AgentTrip.count", 12 do
      post confirm_agent_trip_import_path(task), params: { items: rows }, as: :json
      assert_response :success
    end
    assert_equal 4, @workspace.agent_trips.joins(:current_revision).where(agent_trip_revisions: { destination: "Patagonia soñada" }).count
    assert_equal 1, @workspace.agent_trips.joins(:current_revision).where(agent_trip_revisions: { destination: "Carlos Paz" }).count
  end

  test "USD stays selected and missing currencies and bases default to Argentine pesos and double" do
    assert_equal [ @supplier.id ], Agent::SupplierMatch.candidates(@workspace.agent_suppliers.to_a, "OperadoraUniversal").map(&:id)
    programs = AgentFlyerExamples.multiple_programs.first(2)
    programs.first["fares"].first["currency"] = "USD"
    task = import_programs(programs)
    rows = review_rows(task)
    assert_equal "USD", rows.first["values"]["currency"]
    assert_equal "USD", rows.first["values"]["fares"].first["currency"]
    assert_equal [ "ARS" ], rows.last["values"]["fares"].pluck("currency").uniq
    assert_equal [ "Base doble" ], rows.flat_map { |row| row["values"]["fares"].pluck("label") }.uniq
    get new_agent_trip_path
    assert_select "input[name='agent_trip_revision[region]']", count: 0
    assert_select "select[id='fare_0_currency'] option", count: 2
    assert_select "option[value=ARS][selected]", text: "Pesos Argentinos"
    assert_select "option[value=USD]", text: "Dólares"
    assert_no_difference "AgentTrip.count" do
      post agent_trips_path, params: { agent_trip_revision: { agent_supplier_id: @supplier.id, title: "Moneda inválida", currency: "EUR", price: "100" } }
      assert_response :unprocessable_entity
    end
  end

  test "invalid fare prices roll back the entire confirmation and retain corrections" do
    task = import_programs(AgentFlyerExamples.multiple_bases)
    rows = review_rows(task)
    rows.last["values"]["fares"].last["price"] = "importe inválido"
    assert_no_difference [ "AgentTrip.count", "AgentTripRevision.count" ] do
      post confirm_agent_trip_import_path(task), params: { items: rows }, as: :json
      assert_response :unprocessable_entity
    end
    assert_equal "importe inválido", review_rows(task).last["values"]["fares"].last["price"]
    rows.last["values"]["fares"].last["price"] = "115000"
    post confirm_agent_trip_import_path(task), params: { items: rows }, as: :json
    assert_response :success
  end

  test "imported and reviewed prices always use the per person unit" do
    programs = AgentFlyerExamples.multiple_bases
    programs.first["price_unit"] = "per_group"
    programs.first["fares"].first["price_unit"] = nil
    programs.first["fares"].last["price_unit"] = "per_room"
    task = import_programs(programs)
    rows = review_rows(task)
    assert rows.all? { |row| row["values"]["price_unit"] == "per_person" && row["values"]["fares"].all? { |fare| fare["price_unit"] == "per_person" } }
    rows.each do |row|
      row["values"]["price_unit"] = "per_group"
      row["values"]["fares"].each { |fare| fare["price_unit"] = "per_room" }
    end
    patch review_agent_trip_import_path(task), params: { items: rows }, as: :json
    assert_response :success
    assert task.items.reload.all? { |item| item.review_data["price_unit"] == "per_person" && item.review_data["fares"].all? { |fare| fare["price_unit"] == "per_person" } }
    post confirm_agent_trip_import_path(task), params: {}, as: :json
    assert_response :success
    assert task.items.reload.all? { |item| item.agent_trip_revision.price_unit == "per_person" && item.agent_trip_revision.fares.all? { |fare| fare["price_unit"] == "per_person" } }
  end

  test "manual trip forms save prices per person without a unit selector" do
    get new_agent_trip_path
    assert_response :success
    assert_select "select[name*='[price_unit]']", count: 0
    post agent_trips_path, params: { agent_trip_revision: {
      agent_supplier_id: @supplier.id, title: "Viaje manual", currency: "ARS", price: "105000"
    } }
    assert_response :redirect
    trip = @workspace.agent_trips.order(:created_at).last
    assert_equal "per_person", trip.current_revision.price_unit
    assert_equal [ "per_person" ], trip.current_revision.fares.pluck("price_unit")
    patch agent_trip_path(trip), params: { expected_revision_id: trip.current_revision_id, agent_trip_revision: {
      agent_supplier_id: @supplier.id, title: "Viaje revisado", currency: "ARS", price_unit: "per_group",
      fares: [ { label: "Base doble", price: "115000", currency: "ARS", price_unit: "per_room" } ]
    } }
    assert_response :redirect
    assert_equal "per_person", trip.reload.current_revision.price_unit
    assert_equal [ "per_person" ], trip.current_revision.fares.pluck("price_unit")
    assert_equal 11_500_000, trip.current_revision.price_cents
    get edit_agent_trip_path(trip)
    assert_response :success
    assert_select "select[name*='[price_unit]']", count: 0
  end

  test "published trips show all fare options and subsequent edits preserve them" do
    task = import_programs(AgentFlyerExamples.multiple_bases)
    rows = review_rows(task)
    rows.each { |row| row["selected"] = false }
    rows.last["selected"] = true
    post confirm_agent_trip_import_path(task), params: { items: rows }, as: :json
    assert_response :success
    trip = task.items.last.reload.agent_trip
    trip.publish!
    get agent_public_trip_path(slug: trip.slug)
    assert_response :success
    assert_select ".travel-booking [role=tab]", text: "Base doble"
    assert_select ".travel-booking [role=tabpanel]", text: /115.000,00/
    original = trip.current_revision
    login_agent(@workspace)
    patch agent_trip_path(trip), params: { expected_revision_id: original.id,
      agent_trip_revision: original.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "Título revisado", "price" => "106000") }
    assert_response :redirect
    assert_equal 2, trip.reload.current_revision.fares.size
    assert_equal 10_600_000, trip.current_revision.fares.first["price_cents"]
    assert_equal 11_500_000, trip.current_revision.fares.last["price_cents"]
    assert_equal original.id, trip.published_revision_id
  end
end
