require "test_helper"

class PassengerFormAndRemittanceTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Finanzas Test", slug: "fin-#{SecureRandom.hex(3)}")
    @user = create_user
    @membership = create_membership(company: @company, user: @user, roles: %w[reseller])
    @trip = create_trip(company: @company)
  end

  test "submitting a private form does not occupy seats" do
    form, token = PassengerForm.issue!(company: @company, departure_offer: @trip[:offer], reseller_membership: @membership)
    before = @trip[:departure].available_seats
    form.create_passenger_form_submission!(full_name: "Ana Pérez", document_number: "30111222", document_last4: "1222",
      nationality: "Argentina", departure_stop: @trip[:stop])
    form.update!(submitted_at: Time.current)
    assert_equal form, PassengerForm.find_by_token(token)
    assert_equal before, @trip[:departure].available_seats
  end

  test "a submission cannot select a stop from another departure" do
    form, = PassengerForm.issue!(company: @company, departure_offer: @trip[:offer], reseller_membership: @membership)
    other_trip = create_trip(company: @company)
    submission = form.build_passenger_form_submission(full_name: "Ana Pérez", document_number: "30111222",
      document_last4: "1222", nationality: "Argentina", departure_stop: other_trip[:stop])

    assert_not submission.save
    assert_includes submission.errors[:departure_stop], "no pertenece a la salida del formulario"
  end

  test "verification is idempotent and updates payment financial state" do
    reservation = @company.reservations.create!(departure_offer: @trip[:offer], seller_membership: @membership,
      created_by: @user, code: "R-#{SecureRandom.hex(3)}", channel: "reseller", status: "confirmed")
    payment = reservation.customer_payments.create!(company: @company, recorded_by: @user,
      received_by_membership: @membership, amount_cents: 70_000, method: "cash", received_on: Date.current)
    remittance = @company.remittances.create!(reseller_membership: @membership, declared_by: @user,
      code: "RE-#{SecureRandom.hex(3)}", amount_cents: 70_000, method: "transfer", declared_on: Date.current)
    remittance.remittance_allocations.create!(customer_payment: payment, amount_cents: 70_000)
    remittance.verify!(@user)
    remittance.verify!(@user)
    assert_equal "verified", payment.reload.status
    assert_equal 70_000, payment.remittance_allocations.joins(:remittance).where(remittances: { status: "verified" }).sum(:amount_cents)
  end
end
