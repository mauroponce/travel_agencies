require "test_helper"

class BoardingSyncConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent commands compare their base version while the passenger is locked" do
    company = Company.create!(name: "Embarques", slug: "embarques-#{SecureRandom.hex(4)}")
    reseller_user = create_user
    reseller = create_membership(company:, user: reseller_user, roles: %w[reseller], auto_confirm: true)
    coordinator_user = create_user
    coordinator = create_membership(company:, user: coordinator_user, roles: %w[coordinator])
    trip = create_trip(company:)
    trip[:departure].departure_assignments.create!(membership: coordinator)
    reservation = Reservations::Confirm.call(offer: trip[:offer], actor: reseller_user, membership: reseller,
      channel: "reseller", passengers: [ { full_name: "A Bordo", document_number: "30123456",
        nationality: "Argentina", departure_stop_id: trip[:stop].id } ],
      payment: { amount_cents: 50_000, method: "cash", received_on: Date.current }, idempotency_key: SecureRandom.uuid)
    passenger = reservation.passengers.first
    base_version = passenger.lock_version
    ready = Queue.new
    start = Queue.new

    threads = %w[boarded absent].map do |status|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          Boarding::Sync.call(departure: trip[:departure], membership: coordinator, commands: [ {
            command_id: SecureRandom.uuid, passenger_id: passenger.id, desired_status: status,
            base_version:, occurred_at: Time.current
          } ]).first.fetch(:result)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }

    assert_equal %w[applied conflict], threads.map(&:value).sort
    assert_equal 1, passenger.boarding_events.count
  end

  test "cancelled reservation passengers cannot receive boarding events" do
    company = Company.create!(name: "Cancelados", slug: "cancelados-#{SecureRandom.hex(4)}")
    user = create_user
    membership = create_membership(company:, user:, roles: %w[coordinator])
    trip = create_trip(company:)
    trip[:departure].departure_assignments.create!(membership:)
    reservation = company.reservations.create!(departure_offer: trip[:offer], created_by: user,
      code: "C-#{SecureRandom.hex(3)}", channel: "direct", status: "cancelled")
    passenger = reservation.passengers.create!(company:, departure_stop: trip[:stop], accommodation: trip[:hotel],
      full_name: "Cancelada", document_number: "30999888", document_last4: "9888", nationality: "Argentina")

    assert_raises(ActiveRecord::RecordNotFound) do
      Boarding::Sync.call(departure: trip[:departure], membership:, commands: [ {
        command_id: SecureRandom.uuid, passenger_id: passenger.id, desired_status: "boarded",
        base_version: passenger.lock_version, occurred_at: Time.current
      } ])
    end
  end
end
