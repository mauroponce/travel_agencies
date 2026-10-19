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

  private

  def confirm_one
    Reservations::Confirm.call(offer: @trip[:offer], actor: @user, membership: @membership, channel: "reseller",
      passengers: [ { full_name: "Pasajera", document_number: "30123456", nationality: "Argentina",
        departure_stop_id: @trip[:stop].id } ],
      payment: { amount_cents: 50_000, method: "cash", received_on: Date.current }, idempotency_key: SecureRandom.uuid)
  end
end
