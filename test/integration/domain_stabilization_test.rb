require "test_helper"

class DomainStabilizationTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @company = Company.create!(name: "Estabilización", slug: "estabilizacion-#{SecureRandom.hex(3)}")
    @membership = create_membership(company: @company, user: @user, roles: %w[admin reseller], auto_confirm: true)
    @trip = create_trip(company: @company, capacity: 2)
    login_as(@user)
  end

  test "manifests and boarding screens only include confirmed reservation passengers" do
    active = reservation_with_passenger("Confirmada", "confirmed")
    reservation_with_passenger("Solicitud no confirmada", "requested")
    reservation_with_passenger("Cancelada", "cancelled")

    get departure_manifest_path(@trip[:departure], format: :csv)
    assert_response :success
    assert_includes response.body, active.passengers.first.full_name
    assert_not_includes response.body, "Solicitud no confirmada"
    assert_not_includes response.body, "Cancelada"

    get operation_departure_path(@trip[:departure])
    assert_response :success
    assert_includes response.body, "Confirmada"
    assert_not_includes response.body, "Solicitud no confirmada"
    assert_not_includes response.body, "Cancelada"
  end

  test "departure form updates each stop time and rejects capacity below occupancy" do
    second_point = @company.boarding_points.create!(name: "Segundo punto", address: "Calle 456")
    second_stop = @trip[:departure].departure_stops.create!(boarding_point: second_point, position: 2,
      scheduled_at: @trip[:departure].departs_at + 1.hour, published_name: second_point.name,
      published_address: second_point.address)
    updated_time = @trip[:departure].departs_at + 2.hours

    patch departure_path(@trip[:departure]), params: { departure: {
      capacity: 2, departure_stops_attributes: { "0" => { id: second_stop.id, scheduled_at: updated_time } }
    } }
    assert_redirected_to departure_path(@trip[:departure])
    assert_in_delta updated_time, second_stop.reload.scheduled_at, 1.second

    reservation_with_passenger("Uno", "confirmed", allocate_seat: true)
    reservation_with_passenger("Dos", "confirmed", allocate_seat: true)
    patch departure_path(@trip[:departure]), params: { departure: { capacity: 1 } }
    assert_response :unprocessable_entity
    assert_equal 2, @trip[:departure].reload.capacity
  end

  private

  def reservation_with_passenger(name, status, allocate_seat: false)
    reservation = @company.reservations.create!(departure_offer: @trip[:offer], created_by: @user,
      code: "R-#{SecureRandom.hex(3)}", channel: "direct", status:)
    passenger = reservation.passengers.create!(company: @company, departure_stop: @trip[:stop],
      accommodation: @trip[:hotel], full_name: name, document_number: "30#{SecureRandom.random_number(10**6).to_s.rjust(6, '0')}",
      document_last4: SecureRandom.random_number(10**4).to_s.rjust(4, "0"), nationality: "Argentina")
    SeatAllocation.create!(company: @company, departure: @trip[:departure], passenger:) if allocate_seat
    reservation
  end
end

class PassengerFormConversionTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @company = Company.create!(name: "Formularios", slug: "formularios-#{SecureRandom.hex(3)}")
    @membership = create_membership(company: @company, user: @user, roles: %w[reseller], auto_confirm: true)
    @trip = create_trip(company: @company)
    @form, = PassengerForm.issue!(company: @company, departure_offer: @trip[:offer], reseller_membership: @membership)
    @form.create_passenger_form_submission!(full_name: "Ana Formulario", document_number: "30111222",
      document_last4: "1222", nationality: "Argentina", departure_stop: @trip[:stop], room_type: "Doble")
    @form.update!(submitted_at: Time.current)
    login_as(@user)
  end

  test "received data is visible and converts to one request without occupying a seat" do
    get passenger_form_path(@form)
    assert_response :success
    assert_includes response.body, "Ana Formulario"
    assert_includes response.body, "30111222"

    assert_difference("Reservation.count", 1) do
      assert_no_difference("SeatAllocation.count") { post convert_passenger_form_path(@form) }
    end
    request_reservation = @form.reload.reservation
    assert_equal "requested", request_reservation.status
    assert_equal "Ana Formulario", request_reservation.passengers.first.full_name

    assert_no_difference([ "Reservation.count", "Passenger.count" ]) { post convert_passenger_form_path(@form) }
    assert_redirected_to reservation_path(request_reservation)
  end

  test "an existing request can be confirmed once without duplicating its data" do
    post convert_passenger_form_path(@form)
    request_reservation = @form.reload.reservation
    request_params = { payment: { amount_cents: "500.00", method: "cash", received_on: Date.current } }

    get reservation_path(request_reservation)
    assert_response :success
    assert_includes response.body, "Confirmar reserva"

    assert_no_difference([ "Reservation.count", "Passenger.count" ]) do
      assert_difference([ "SeatAllocation.count", "CustomerPayment.count" ], 1) do
        post confirm_reservation_path(request_reservation), params: request_params
      end
    end
    confirmed = request_reservation.reload
    assert_equal "confirmed", confirmed.status
    assert_equal "cash", confirmed.customer_payments.sole.method

    assert_no_difference([ "Reservation.count", "Passenger.count", "SeatAllocation.count", "CustomerPayment.count" ]) do
      post confirm_reservation_path(confirmed), params: request_params
    end
    assert_redirected_to reservation_path(confirmed)

    get reservation_path(confirmed)
    assert_not_includes response.body, "Confirmar reserva"
  end

  test "a sold out confirmation shows an error and preserves the request" do
    post convert_passenger_form_path(@form)
    request_reservation = @form.reload.reservation
    @trip[:departure].update!(capacity: 1)
    occupied = @company.reservations.create!(departure_offer: @trip[:offer], seller_membership: @membership,
      created_by: @user, code: "OCUPADA-#{SecureRandom.hex(2)}", channel: "reseller", status: "confirmed")
    passenger = occupied.passengers.create!(company: @company, departure_stop: @trip[:stop],
      accommodation: @trip[:hotel], full_name: "Cupo ocupado", document_number: "30999888",
      document_last4: "9888", nationality: "Argentina")
    SeatAllocation.create!(company: @company, departure: @trip[:departure], passenger:)

    assert_no_difference([ "SeatAllocation.count", "CustomerPayment.count", "CommissionEntry.count" ]) do
      post confirm_reservation_path(request_reservation), params: {
        payment: { amount_cents: "500.00", method: "cash", received_on: Date.current }
      }
    end

    assert_redirected_to reservation_path(request_reservation)
    follow_redirect!
    assert_includes response.body, "No quedan cupos suficientes"
    assert_equal "requested", request_reservation.reload.status
    assert_equal "Ana Formulario", request_reservation.passengers.sole.full_name
  end
end
