require "test_helper"

class PassengerFormConversionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent conversions create a single request" do
    company = Company.create!(name: "Conversión", slug: "conversion-#{SecureRandom.hex(4)}")
    user = create_user
    membership = create_membership(company:, user:, roles: %w[reseller])
    trip = create_trip(company:)
    form, = PassengerForm.issue!(company:, departure_offer: trip[:offer], reseller_membership: membership)
    form.create_passenger_form_submission!(full_name: "Solicitud Única", document_number: "30111222",
      document_last4: "1222", nationality: "Argentina", departure_stop: trip[:stop])
    form.update!(submitted_at: Time.current)
    ready = Queue.new
    start = Queue.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          PassengerForms::ConvertToRequest.call(form: PassengerForm.find(form.id), actor: user, membership:).id
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    reservation_ids = threads.map(&:value)

    assert_equal 1, reservation_ids.uniq.size
    assert_equal 1, Reservation.where(id: reservation_ids).count
    assert_equal reservation_ids.first, form.reload.reservation_id
  end
end
