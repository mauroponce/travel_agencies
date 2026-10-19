require "test_helper"

class ScreenSmokeTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user(name: "Carolina Demo")
    @company = Company.create!(name: "Pantallas Viajes", slug: "pantallas-#{SecureRandom.hex(3)}", whatsapp: "5491155550000")
    @membership = create_membership(company: @company, user: @user, roles: %w[admin reseller coordinator])
    @trip = create_trip(company: @company)
    @trip[:departure].departure_assignments.create!(membership: @membership)
    login_as(@user)
  end

  test "main admin and public screens render" do
    [ dashboard_path, departure_offers_path, travel_packages_path, departures_path, reservations_path,
     customer_payments_path, remittances_path, commissions_path, catalog_path, team_members_path,
     notifications_path, operation_departure_path(@trip[:departure]) ].each do |path|
      get path
      assert_response :success, "expected #{path} to render"
    end
    get public_trip_path(@company.slug, @trip[:offer].slug)
    assert_response :success
    assert_select "h1", text: /Mendoza/
  end

  test "publication notifies authorized resellers" do
    @trip[:offer].update!(status: "draft")
    assert_difference("Notification.count", 1) do
      post publish_departure_offer_path(@trip[:offer])
    end
    assert_redirected_to departure_offer_path(@trip[:offer])
  end

  test "reservation form persists a passenger and occupies a seat" do
    assert_difference([ "Reservation.count", "Passenger.count", "SeatAllocation.count" ], 1) do
      post reservations_path, params: {
        departure_offer_id: @trip[:offer].id, idempotency_key: SecureRandom.uuid,
        passengers: { "0" => { full_name: "María Prueba", document_number: "30123456", nationality: "Argentina",
          departure_stop_id: @trip[:stop].id, room_type: "Doble" } },
        payment: { amount_cents: 50_000, method: "cash", received_on: Date.current }
      }
    end
    assert_response :redirect
    assert_equal 5, @trip[:departure].available_seats
  end

  test "public passenger form can be submitted only once without a seat" do
    form, token = PassengerForm.issue!(company: @company, departure_offer: @trip[:offer], reseller_membership: @membership)
    assert_no_difference("SeatAllocation.count") do
      post public_passenger_form_path(token), params: { passenger_form_submission: {
        full_name: "Pasajera Formulario", document_number: "30999888", nationality: "Argentina",
        departure_stop_id: @trip[:stop].id, room_type: "Doble"
      } }
    end
    assert_response :success
    assert form.reload.submitted_at
    post public_passenger_form_path(token), params: { passenger_form_submission: { full_name: "Duplicado" } }
    assert_response :gone
  end

  test "price update is visible on permanent public URL" do
    post departure_offer_fare_versions_path(@trip[:offer]), params: { fare_version: {
      price_cents: "250000", service_fee_cents: "10000", deposit_type: "fixed", deposit_cents: "50000",
      promotion_label: "SUPER SALE"
    } }
    travel 1.second
    get public_trip_path(@company.slug, @trip[:offer].slug)
    assert_response :success
    assert_includes response.body, "$2.500,00"
    assert_includes response.body, "SUPER SALE"
  end
end
