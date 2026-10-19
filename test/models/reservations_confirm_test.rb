require "test_helper"

class ReservationsConfirmTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Empresa Test", slug: "empresa-#{SecureRandom.hex(3)}")
    @user = create_user
    @membership = create_membership(company: @company, user: @user, roles: %w[reseller], auto_confirm: true)
    @trip = create_trip(company: @company, capacity: 2)
    @company.commission_rules.create!(reseller_membership: @membership, kind: "percentage", percentage: 10, status: "active")
  end

  test "confirmation reserves shared departure inventory and freezes fare" do
    reservation = confirm(passengers: 1, key: "first")
    assert_equal "confirmed", reservation.status
    assert_equal 1, @trip[:departure].available_seats
    assert_equal 100_000, reservation.unit_price_cents
    assert_equal 11_000, reservation.commission_entry.amount_cents

    @trip[:offer].fare_versions.create!(price_cents: 250_000, service_fee_cents: 10_000,
      deposit_type: "fixed", deposit_cents: 50_000, valid_from: 1.minute.from_now)
    assert_equal 100_000, reservation.reload.unit_price_cents
  end

  test "two package offers consume the same bus inventory" do
    second_package = @company.travel_packages.create!(destination: @trip[:destination], name: "Mendoza Confort",
      days: 6, nights: 3)
    second_offer = @company.departure_offers.create!(travel_package: second_package, departure: @trip[:departure],
      accommodation: @trip[:hotel], slug: "confort-#{SecureRandom.hex(2)}", status: "published")
    second_offer.fare_versions.create!(price_cents: 150_000, service_fee_cents: 10_000, deposit_type: "fixed",
      deposit_cents: 50_000, valid_from: 1.hour.ago)
    confirm(passengers: 1, key: "package-one")
    Reservations::Confirm.call(offer: second_offer, actor: @user, membership: @membership, channel: "reseller",
      passengers: passenger_attributes(1), payment: payment_attributes(50_000), idempotency_key: "package-two")
    assert_equal 0, @trip[:offer].available_seats
    assert_equal 0, second_offer.available_seats
  end

  test "idempotency prevents duplicate seats and sold out rejects excess" do
    first = confirm(passengers: 2, key: "same-command")
    duplicate = confirm(passengers: 2, key: "same-command")
    assert_equal first.id, duplicate.id
    assert_equal 2, @trip[:departure].seat_allocations.where(status: "active").count
    assert_raises(Reservations::Confirm::SoldOut) { confirm(passengers: 1, key: "excess") }
  end

  test "direct sale never creates a commission" do
    admin = create_membership(company: @company, user: create_user, roles: %w[admin])
    reservation = Reservations::Confirm.call(offer: @trip[:offer], actor: admin.user, membership: admin, channel: "direct",
      passengers: passenger_attributes(1), payment: payment_attributes(50_000), idempotency_key: "direct")
    assert_nil reservation.commission_entry
  end

  test "confirmation requires a published offer and an open departure" do
    @trip[:departure].update!(status: "draft")
    assert_raises(Reservations::Confirm::NotAvailable) { confirm(passengers: 1, key: "closed-departure") }

    @trip[:departure].update!(status: "open")
    @trip[:offer].update!(status: "unpublished")
    assert_raises(Reservations::Confirm::NotAvailable) { confirm(passengers: 1, key: "unpublished-offer") }
    assert_equal 0, @trip[:departure].occupied_seats
  end

  test "confirmation transitions an existing request and freezes the current fare" do
    request = requested_reservation
    admin_user = create_user
    create_membership(company: @company, user: admin_user, roles: %w[admin])
    @trip[:offer].fare_versions.create!(price_cents: 120_000, service_fee_cents: 12_000,
      deposit_type: "fixed", deposit_cents: 60_000, promotion_label: "Tarifa actual",
      valid_from: 1.minute.ago)

    assert_difference("Notification.count", 2) do
      assert_no_difference([ "Reservation.count", "Passenger.count" ]) do
        assert_difference([ "SeatAllocation.count", "CustomerPayment.count", "CommissionEntry.count", "AuditEvent.count" ], 1) do
          Reservations::Confirm.call(reservation: request, actor: @user, membership: @membership,
            payment: payment_attributes(60_000))
        end
      end
    end

    assert_equal "confirmed", request.reload.status
    assert_equal 120_000, request.unit_price_cents
    assert_equal({ "deposit_type" => "fixed", "promotion_label" => "Tarifa actual" }, request.terms_snapshot)
    assert_equal 1, @trip[:departure].occupied_seats
    recipients = Notification.where(company: @company, event_type: "reservation_confirmed").pluck(:user_id)
    assert_equal [ @user.id, admin_user.id ].sort, recipients.sort
  end

  test "confirming an existing request twice does not duplicate side effects" do
    request = requested_reservation
    2.times do
      Reservations::Confirm.call(reservation: request, actor: @user, membership: @membership,
        payment: payment_attributes(50_000))
    end

    assert_equal 1, request.reload.customer_payments.count
    assert_equal 1, request.passengers.joins(:seat_allocation).count
    assert_equal 1, CommissionEntry.where(reservation: request).count
    assert_equal 1, AuditEvent.where(auditable_type: "Reservation", auditable_id: request.id,
      action: "reservation.confirmed").count
  end

  test "sold out confirmation preserves the pending request" do
    request = requested_reservation
    confirm(passengers: 2, key: "fill-departure")

    assert_raises(Reservations::Confirm::SoldOut) do
      Reservations::Confirm.call(reservation: request, actor: @user, membership: @membership,
        payment: payment_attributes(50_000))
    end

    assert_equal "requested", request.reload.status
    assert_empty request.customer_payments
    assert_nil request.passengers.first.seat_allocation
  end

  test "request confirmation rechecks reseller authorization" do
    request = requested_reservation
    @membership.reseller_authorization.update!(auto_confirm_enabled: false)

    assert_raises(Reservations::Confirm::NotAuthorized) do
      Reservations::Confirm.call(reservation: request, actor: @user, membership: @membership,
        payment: payment_attributes(50_000))
    end

    assert_equal "requested", request.reload.status
    assert_empty request.customer_payments
    assert_equal 0, @trip[:departure].occupied_seats
  end

  private

  def confirm(passengers:, key:)
    Reservations::Confirm.call(offer: @trip[:offer], actor: @user, membership: @membership, channel: "reseller",
      passengers: passenger_attributes(passengers), payment: payment_attributes(50_000 * passengers), idempotency_key: key)
  end

  def passenger_attributes(count)
    count.times.map do |index|
      { full_name: "Pasajero #{index}", document_number: "3012345#{index}", nationality: "Argentina",
       departure_stop_id: @trip[:stop].id, room_type: "Doble" }
    end
  end

  def payment_attributes(amount)
    { amount_cents: amount, method: "cash", received_on: Date.current }
  end

  def requested_reservation
    reservation = @company.reservations.create!(departure_offer: @trip[:offer], seller_membership: @membership,
      created_by: @user, code: "SOL-#{SecureRandom.hex(3)}", channel: "reseller", status: "requested",
      unit_price_cents: 100_000, unit_fee_cents: 10_000, minimum_payment_cents: 50_000)
    reservation.passengers.create!(company: @company, departure_stop: @trip[:stop], accommodation: @trip[:hotel],
      full_name: "Pasajera Solicitada", document_number: "30111222", document_last4: "1222",
      nationality: "Argentina")
    reservation
  end
end
