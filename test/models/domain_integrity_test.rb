require "test_helper"

class DomainIntegrityTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Integridad", slug: "integridad-#{SecureRandom.hex(3)}")
    @user = create_user
    @membership = create_membership(company: @company, user: @user, roles: %w[reseller], auto_confirm: true)
    @trip = create_trip(company: @company, capacity: 2)
  end

  test "an offer with reservations cannot change departure" do
    confirm_one
    other = create_trip(company: @company)

    assert_not @trip[:offer].update(departure: other[:departure])
    assert_includes @trip[:offer].errors[:departure], "no puede cambiar porque la oferta ya tiene reservas"
  end

  test "departure capacity cannot fall below active occupied seats" do
    Reservations::Confirm.call(offer: @trip[:offer], actor: @user, membership: @membership, channel: "reseller",
      passengers: 2.times.map { |index| { full_name: "Pasajera #{index}", document_number: "3012345#{index}",
        nationality: "Argentina", departure_stop_id: @trip[:stop].id } },
      payment: { amount_cents: 100_000, method: "cash", received_on: Date.current }, idempotency_key: SecureRandom.uuid)

    assert_not @trip[:departure].update_with_inventory_lock(capacity: 1)
    assert_equal 2, @trip[:departure].reload.capacity
  end

  test "money parser converts Argentine peso inputs to integer cents" do
    assert_equal 123_456, MoneyParser.call("1.234,56")
    assert_equal 123_456, MoneyParser.call("1234.56")
    assert_raises(MoneyParser::InvalidAmount) { MoneyParser.call("10.999") }
  end

  test "cross company catalog and operational associations are rejected" do
    other_company = Company.create!(name: "Otra", slug: "otra-#{SecureRandom.hex(3)}")
    other_trip = create_trip(company: other_company)

    package = @company.travel_packages.new(destination: other_trip[:destination], name: "Inválido", days: 2, nights: 1)
    assert_not package.valid?
    assert_includes package.errors[:destination], "debe pertenecer a la empresa"

    stage = @trip[:route].route_stages.new(boarding_point: other_trip[:point], position: 2, kind: "boarding")
    assert_not stage.valid?

    room = @company.room_assignments.new(departure: @trip[:departure], accommodation: other_trip[:hotel], room_type: "Doble")
    assert_not room.valid?
  end

  test "database composite foreign keys reject bypassing model tenant validation" do
    other_company = Company.create!(name: "Otra DB", slug: "otra-db-#{SecureRandom.hex(3)}")
    other_trip = create_trip(company: other_company)

    assert_raises(ActiveRecord::InvalidForeignKey) do
      TravelPackage.insert_all!([ {
        id: SecureRandom.uuid, company_id: @company.id, destination_id: other_trip[:destination].id,
        name: "Cruce", days: 2, nights: 1, included_services: [], excluded_services: [], faqs: {},
        created_at: Time.current, updated_at: Time.current
      } ])
    end
  end

  test "reservation states only move from requested to confirmed to cancelled" do
    request = @company.reservations.create!(departure_offer: @trip[:offer], seller_membership: @membership,
      created_by: @user, code: "STATE-#{SecureRandom.hex(3)}", channel: "reseller", status: "requested")

    assert_not request.update(status: "cancelled")
    assert_includes request.errors[:status], "no admite la transición requested → cancelled"
    request.update!(status: "confirmed")
    request.update!(status: "cancelled")
    assert_not request.update(status: "confirmed")
  end

  test "confirmed prices and commission rule snapshots stay frozen" do
    @company.commission_rules.create!(reseller_membership: @membership, kind: "percentage", percentage: 10,
      status: "active")
    reservation = confirm_one
    entry = reservation.commission_entry

    assert_not reservation.update(unit_price_cents: reservation.unit_price_cents + 1)
    assert_not entry.update(amount_cents: entry.amount_cents + 1)
    entry.reload
    entry.update!(status: "payable")
    assert_equal "payable", entry.reload.status
  end

  private

  def confirm_one
    Reservations::Confirm.call(offer: @trip[:offer], actor: @user, membership: @membership, channel: "reseller",
      passengers: [ { full_name: "Pasajera", document_number: "30123456", nationality: "Argentina",
        departure_stop_id: @trip[:stop].id } ],
      payment: { amount_cents: 50_000, method: "cash", received_on: Date.current }, idempotency_key: SecureRandom.uuid)
  end
end
