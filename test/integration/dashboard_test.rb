require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Admin Dashboard")
    @company = Company.create!(name: "Cadence Viajes", slug: "cadence-#{SecureRandom.hex(3)}")
    @admin = create_membership(company: @company, user: @user, roles: %w[admin])
    @trip = create_trip(company: @company, capacity: 10)
    login_as(@user)
  end

  test "renders real scoped metrics, translated states and real routes" do
    reseller_user = create_user
    reseller = create_membership(company: @company, user: reseller_user, roles: %w[reseller])
    reservation = @company.reservations.create!(departure_offer: @trip[:offer], created_by: @user,
      code: "CAD-CONFIRMADA", channel: "direct", status: "confirmed", confirmed_at: Time.current)
    passenger = reservation.passengers.create!(company: @company, departure_stop: @trip[:stop],
      accommodation: @trip[:hotel], full_name: "Persona Visible", document_number: "30123456",
      document_last4: "3456", nationality: "Argentina")
    @company.seat_allocations.create!(departure: @trip[:departure], passenger:)
    @company.reservations.create!(departure_offer: @trip[:offer], seller_membership: reseller, created_by: reseller_user,
      code: "CAD-SOLICITADA", channel: "reseller", status: "requested")
    @company.reservations.create!(departure_offer: @trip[:offer], created_by: @user,
      code: "CAD-CANCELADA", channel: "direct", status: "cancelled", cancelled_at: Time.current)

    reservation.customer_payments.create!(company: @company, recorded_by: @user, received_by_membership: reseller,
      amount_cents: 123_456, method: "cash", received_on: Date.current, status: "declared")
    @company.remittances.create!(reseller_membership: reseller, declared_by: reseller_user,
      code: "CAD-REND", amount_cents: 45_678, method: "cash", status: "declared", declared_on: Date.current)

    other_company = Company.create!(name: "Otra Agencia", slug: "otra-#{SecureRandom.hex(3)}")
    other_trip = create_trip(company: other_company)
    other_company.reservations.create!(departure_offer: other_trip[:offer], created_by: create_user,
      code: "NO-DEBE-APARECER", channel: "direct", status: "requested")

    get dashboard_path

    assert_response :success
    assert_select "h1", text: /Resumen general/
    assert_select "[aria-label='Indicadores operativos'] .dashboard-kpi", count: 4
    assert_select "article[aria-label='Pasajeros confirmados: 1']"
    assert_select "article[aria-label='Cupos por vender: 9']"
    assert_includes response.body, MoneyFormatter.call(123_456)
    assert_includes response.body, MoneyFormatter.call(45_678)
    assert_includes response.body, "Confirmada"
    assert_includes response.body, "Solicitada"
    assert_includes response.body, "Cancelada"
    assert_select "a[href='#{new_departure_offer_path}']", text: /Nueva oferta/
    assert_select "a[href='#{departure_path(@trip[:departure])}']"
    assert_select "a[href='#{operation_departure_path(@trip[:departure])}']"
    assert_select ".dashboard-promo", count: 0
    assert_not_includes response.body, "NO-DEBE-APARECER"
  end

  test "filters the full departure scope before applying the visible list limit" do
    6.times { create_trip(company: @company, capacity: 20) }
    low_trip = create_trip(company: @company, capacity: 4)
    low_trip[:departure].update!(departs_at: 60.days.from_now)

    get dashboard_path

    assert_select "article[aria-label='Salidas próximas: 8']"
    assert_select ".dashboard-table-footer", text: /Mostrando 5 de 8/

    get dashboard_path, params: { departure_filter: "low" }

    assert_response :success
    assert_includes response.body, low_trip[:departure].code
    assert_select ".dashboard-table-footer", text: /Mostrando 1 de 1/
  end

  test "guards occupancy calculation when a legacy object reports zero capacity" do
    legacy_departure = Struct.new(:capacity, :occupied_seats).new(0, 3)

    assert_equal 0, ApplicationController.helpers.occupancy_percentage(legacy_departure)
  end
end
