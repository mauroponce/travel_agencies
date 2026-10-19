require "test_helper"

class ReservationConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous confirmations cannot oversell the last seat" do
    company = Company.create!(name: "Concurrencia", slug: "concurrency-#{SecureRandom.hex(4)}")
    user = create_user
    membership = create_membership(company:, user:, roles: %w[reseller], auto_confirm: true)
    trip = create_trip(company:, capacity: 1)
    ready = Queue.new
    start = Queue.new

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          Reservations::Confirm.call(offer: trip[:offer], actor: user, membership:, channel: "reseller",
            passengers: [ { full_name: "Concurrente #{index}", document_number: "3012345#{index}", nationality: "Argentina",
              departure_stop_id: trip[:stop].id } ],
            payment: { amount_cents: 50_000, method: "cash", received_on: Date.current },
            idempotency_key: "concurrent-#{index}")
          :confirmed
        rescue Reservations::Confirm::SoldOut
          :sold_out
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    assert_equal [ :confirmed, :sold_out ], results.sort
    assert_equal 1, trip[:departure].seat_allocations.where(status: "active").count
    assert_equal 0, trip[:departure].available_seats
  end

  test "simultaneous confirmation of one request creates side effects once" do
    company = Company.create!(name: "Solicitud concurrente", slug: "request-concurrency-#{SecureRandom.hex(4)}")
    user = create_user
    membership = create_membership(company:, user:, roles: %w[reseller], auto_confirm: true)
    trip = create_trip(company:, capacity: 1)
    company.commission_rules.create!(reseller_membership: membership, kind: "percentage", percentage: 10,
      status: "active")
    reservation = company.reservations.create!(departure_offer: trip[:offer], seller_membership: membership,
      created_by: user, code: "SOL-#{SecureRandom.hex(3)}", channel: "reseller", status: "requested")
    reservation.passengers.create!(company:, departure_stop: trip[:stop], accommodation: trip[:hotel],
      full_name: "Solicitud Única", document_number: "30111222", document_last4: "1222", nationality: "Argentina")
    ready = Queue.new
    start = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          Reservations::Confirm.call(reservation: Reservation.find(reservation.id), actor: user, membership:,
            payment: { amount_cents: 50_000, method: "cash", received_on: Date.current }).id
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }

    assert_equal [ reservation.id ], threads.map(&:value).uniq
    assert_equal "confirmed", reservation.reload.status
    assert_equal 1, reservation.customer_payments.count
    assert_equal 1, reservation.passengers.joins(:seat_allocation).count
    assert_equal 1, CommissionEntry.where(reservation:).count
    assert_equal 0, trip[:departure].available_seats
  end
end
