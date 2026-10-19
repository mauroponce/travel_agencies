require "test_helper"

class RemittanceConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent partial remittances cannot allocate more than the payment" do
    company = Company.create!(name: "Rendiciones", slug: "rendiciones-#{SecureRandom.hex(4)}")
    user = create_user
    membership = create_membership(company:, user:, roles: %w[reseller])
    trip = create_trip(company:)
    reservation = company.reservations.create!(departure_offer: trip[:offer], seller_membership: membership,
      created_by: user, code: "R-#{SecureRandom.hex(3)}", channel: "reseller", status: "confirmed")
    payment = reservation.customer_payments.create!(company:, recorded_by: user, received_by_membership: membership,
      amount_cents: 10_000, method: "cash", received_on: Date.current)
    ready = Queue.new
    start = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          Remittances::Create.call(company:, membership:, actor: user, allocations: { payment.id => 7_000 },
            method: "transfer", declared_on: Date.current)
          :created
        rescue ActiveRecord::RecordInvalid
          :rejected
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }

    assert_equal [ :created, :rejected ], threads.map(&:value).sort
    assert_equal 7_000, payment.reload.allocated_cents
    assert_equal 3_000, payment.pending_remittance_cents

    final = Remittances::Create.call(company:, membership:, actor: user, allocations: { payment.id => 3_000 },
      method: "transfer", declared_on: Date.current,
      proof: { io: StringIO.new("proof"), filename: "proof.pdf", content_type: "application/pdf" })
    assert_equal 2, payment.remittance_allocations.count
    assert_equal 0, payment.pending_remittance_cents
    assert final.proof.attached?
  end
end
