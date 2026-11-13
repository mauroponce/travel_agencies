require "test_helper"
require_relative "../support_agent_data"

class AgentPublicCatalogQueryTest < ActiveSupport::TestCase
  include AgentTestData

  setup do
    @workspace = agent_workspace
    @supplier = @workspace.agent_suppliers.create!(name: "Empresa privada")
  end

  test "typed destinations ignore accents while selected destinations match exactly" do
    cordoba = publish(destination: "Córdoba")
    sierras = publish(destination: "Córdoba Sierras")
    publish(destination: "Mendoza", title: "Córdoba solamente en el título")
    assert_equal [ cordoba.id, sierras.id ].sort, query(destination_query: "CORDOBA").trips.pluck(:id).sort
    assert_equal [ cordoba.id ], query(destination: "Córdoba", destination_query: "Mendoza").trips.pluck(:id)
    assert_empty query(destination_query: "%_").trips
  end

  test "month duration transport and alphabetic sorting combine on published revisions" do
    month = 2.months.from_now.to_date.beginning_of_month
    short = publish(destination: "Zárate", departs_on: month, duration_days: 4, transport: "Bus")
    long = publish(destination: "Ávila", departs_on: month.end_of_month, duration_days: 7, transport: "Avión")
    publish(destination: "Otra salida", departs_on: month.next_month, duration_days: 6)
    filter = { month: month.strftime("%Y-%m") }
    assert_equal [ long.id, short.id ], query(**filter, sort: "destination_asc").trips.pluck(:id)
    assert_equal [ short.id ], query(**filter, duration: "4").trips.pluck(:id)
    assert_equal [ long.id ], query(**filter, duration: "7").trips.pluck(:id)
    assert_equal [ long.id ], query(**filter, transport: "Avión").trips.pluck(:id)
    %w[2030-13 not-a-month 2030-1].each { |value| assert_empty query(month: value).trips }
  end

  test "price ordering compares one currency and unit and otherwise preserves departure order" do
    early = publish(price_cents: 90_000, departs_on: 1.month.from_now.to_date)
    cheap = publish(price_cents: 40_000, departs_on: 2.months.from_now.to_date)
    assert_equal [ cheap.id, early.id ], query(sort: "price_asc").trips.pluck(:id)
    dollar = publish(currency: "USD", price_cents: 100, departs_on: 3.months.from_now.to_date)
    mixed = query(sort: "price_asc")
    assert mixed.price_sort_warning?
    assert_equal [ early.id, cheap.id, dollar.id ], mixed.trips.pluck(:id)
    assert_equal [ cheap.id, early.id ], query(sort: "price_asc", currency: "ARS").trips.pluck(:id)
    publish(price_unit: "per_group")
    assert query(sort: "price_asc", currency: "ARS").price_sort_warning?
    assert_not query(sort: "price_asc", currency: "ARS", price_unit: "per_person").price_sort_warning?
  end

  test "public filter options never include private revisions paused suppliers or foreign workspaces" do
    trip = publish(destination: "Destino público", transport: "Bus")
    original = trip.published_revision
    Agent::SaveTrip.call(workspace: @workspace, trip:, expected_revision_id: trip.current_revision_id,
      attributes: original.attributes.slice(*AgentTripRevision::FIELDS).merge("destination" => "Destino privado", "transport" => "Transporte privado"))
    agent_trip(workspace: @workspace, destination: "Borrador", transport: "Secreto")
    publish(destination: "Archivado").update!(status: "archived")
    agent_trip(workspace: agent_workspace, destination: "Ajeno", transport: "Ajeno").publish!
    assert_equal [ "Destino público" ], query.destinations
    assert_equal [ "Bus" ], query.transports
    assert_equal [ original.departs_on.beginning_of_month ], query.months
    @supplier.update!(status: "paused")
    assert_empty query.destinations
    assert_empty query.transports
    assert_empty query.months
  end

  private

  def publish(**attributes)
    agent_trip(workspace: @workspace, supplier: @supplier, returns_on: nil, **attributes).tap(&:publish!)
  end

  def query(**filters)
    Agent::PublicCatalogQuery.new(workspace: @workspace, filters:)
  end
end
