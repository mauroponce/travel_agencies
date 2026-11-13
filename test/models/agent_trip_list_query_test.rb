require "test_helper"
require_relative "../support_agent_data"

class AgentTripListQueryTest < ActiveSupport::TestCase
  include AgentTestData

  setup do
    @workspace = agent_workspace
    @supplier = @workspace.agent_suppliers.create!(name: "Cóndor Viajes")
  end

  test "three explicit groups normalize missing invalid and legacy states to published" do
    trips = %w[published draft unpublished archived].index_with do |status|
      trip = agent_trip(workspace: @workspace, supplier: @supplier)
      status == "published" ? trip.publish! : trip.update!(status:)
      trip
    end
    [ nil, "", "all", "unpublished", "expired", [], {} ].each do |tab|
      query = Agent::TripListQuery.new(workspace: @workspace, tab:)
      assert_equal "published", query.tab
      assert_equal [ trips["published"].id ], query.trips.pluck(:id)
    end
    query = Agent::TripListQuery.new(workspace: @workspace, tab: "drafts")
    assert_equal [ trips["unpublished"].id, trips["draft"].id ], query.trips.pluck(:id)
    assert_equal [ trips["archived"].id ], Agent::TripListQuery.new(workspace: @workspace, tab: "archived").trips.pluck(:id)
    assert_equal({ "published" => 1, "drafts" => 2, "archived" => 1 }, query.counts)
  end

  test "creation order overrides departure and update dates and breaks ties by id" do
    old = agent_trip(workspace: @workspace, departs_on: 1.day.from_now.to_date)
    newer = agent_trip(workspace: @workspace, departs_on: 6.months.from_now.to_date, returns_on: nil)
    newest = agent_trip(workspace: @workspace, departs_on: 3.months.from_now.to_date, returns_on: nil)
    old.update_columns(created_at: 3.days.ago, updated_at: 1.day.from_now)
    timestamp = 1.day.ago
    newer.update_columns(created_at: timestamp)
    newest.update_columns(created_at: timestamp)
    %w[published drafts archived].each do |tab|
      status = tab == "drafts" ? "draft" : tab
      [ old, newer, newest ].each { |trip| status == "published" ? trip.publish! : trip.update!(status:) }
      query = Agent::TripListQuery.new(workspace: @workspace, tab:, filters: { sort: "price_asc", status: "expired" })
      assert_equal [ newer.id, newest.id ].sort.reverse + [ old.id ], query.trips.pluck(:id)
    end
  end

  test "title destination and supplier search ignores case and accents and escapes wildcards" do
    trip = agent_trip(workspace: @workspace, supplier: @supplier, title: "Vacaciones en el sur", destination: "Río Negro")
    %w[VACACIONES rio CONDOR].each do |q|
      assert_equal [ trip.id ], Agent::TripListQuery.new(workspace: @workspace, tab: "drafts", filters: { q: }).trips.pluck(:id)
    end
    [ "%", "_", "' OR 1=1 --" ].each do |q|
      assert_empty Agent::TripListQuery.new(workspace: @workspace, tab: "drafts", filters: { q: }).trips
    end
  end

  test "all counters share filters and workspace isolation before pagination" do
    attrs = { workspace: @workspace, supplier: @supplier, destination: "Mendoza", departs_on: 3.months.from_now.to_date, returns_on: nil, currency: "USD" }
    21.times { agent_trip(**attrs).publish! }
    draft = agent_trip(**attrs)
    unpublished = agent_trip(**attrs)
    unpublished.update!(status: "unpublished")
    archived = agent_trip(**attrs)
    archived.update!(status: "archived")
    agent_trip(**attrs, currency: "ARS").publish!
    agent_trip(**attrs, departs_on: 6.months.from_now.to_date).publish!
    agent_trip(workspace: @workspace, currency: "USD").publish!
    agent_trip(workspace: agent_workspace, destination: "Mendoza", currency: "USD").publish!
    filters = { q: "mendoza", supplier_id: @supplier.id, from: 2.months.from_now.to_date.iso8601, to: 4.months.from_now.to_date.iso8601, currency: "USD" }
    query = Agent::TripListQuery.new(workspace: @workspace, filters:)
    records, page = Pagination.call(query.trips, page: 2, per_page: 20)
    assert_equal 1, records.size
    assert_equal 21, page.total_count
    assert_equal({ "published" => 21, "drafts" => 2, "archived" => 1 }, query.counts)
    assert_equal [ unpublished.id, draft.id ], Agent::TripListQuery.new(workspace: @workspace, tab: "drafts", filters:).trips.pluck(:id)
  end

  test "effective public visibility and pending edits never change persisted tab membership" do
    trip = agent_trip(workspace: @workspace, supplier: @supplier)
    trip.publish!
    original = trip.published_revision
    Agent::SaveTrip.call(workspace: @workspace, trip:, expected_revision_id: trip.current_revision_id,
      attributes: original.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "Cambios pendientes"))
    @supplier.update!(status: "paused")
    travel_to(4.months.from_now) do
      assert_equal [ trip.id ], Agent::TripListQuery.new(workspace: @workspace).trips.pluck(:id)
      assert_empty Agent::TripListQuery.new(workspace: @workspace, tab: "drafts").trips
    end
    assert_equal original.id, trip.reload.published_revision_id
  end

  test "invalid dates and foreign supplier filters return no records or counter leaks" do
    agent_trip(workspace: @workspace).publish!
    foreign = agent_trip(workspace: agent_workspace)
    [ { from: "invalid" }, { supplier_id: foreign.current_revision.agent_supplier_id } ].each do |filters|
      query = Agent::TripListQuery.new(workspace: @workspace, filters:)
      assert_empty query.trips
      assert_equal({ "published" => 0, "drafts" => 0, "archived" => 0 }, query.counts)
    end
  end

  test "public catalog keeps departure order published revisions and its existing search semantics" do
    early = agent_trip(workspace: @workspace, supplier: @supplier, title: "Original", departs_on: 1.month.from_now.to_date)
    late = agent_trip(workspace: @workspace, supplier: @supplier, departs_on: 4.months.from_now.to_date, returns_on: nil)
    [ early, late ].each(&:publish!)
    Agent::SaveTrip.call(workspace: @workspace, trip: early, expected_revision_id: early.current_revision_id,
      attributes: early.current_revision.attributes.slice(*AgentTripRevision::FIELDS).merge("title" => "Privado", "departs_on" => 6.months.from_now.to_date, "returns_on" => nil))
    assert_equal [ early.id, late.id ], Agent::CatalogQuery.call(workspace: @workspace, public_view: true).pluck(:id)
    assert_equal [ early.id ], Agent::CatalogQuery.call(workspace: @workspace, public_view: true, filters: { q: "original" }).pluck(:id)
    assert_empty Agent::CatalogQuery.call(workspace: @workspace, public_view: true, filters: { q: "privado" })
    assert_empty Agent::CatalogQuery.call(workspace: @workspace, public_view: true, filters: { q: "condor" })
  end
end
