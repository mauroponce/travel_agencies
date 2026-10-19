require "test_helper"

class RemittancesTest < ActionDispatch::IntegrationTest
  setup do
    @company = Company.create!(name: "Rendiciones web", slug: "rendiciones-web-#{SecureRandom.hex(3)}")
    @user = create_user
    @membership = create_membership(company: @company, user: @user, roles: %w[reseller])
    @trip = create_trip(company: @company)
    @payments = [ 3_000_000, 2_000_000, 1_500_000 ].map { |amount| create_payment(amount) }
    login_as(@user)
  end

  test "blank unselected amounts are ignored" do
    assert_difference([ "Remittance.count", "RemittanceAllocation.count" ], 1) do
      post remittances_path, params: {
        method: "cash", declared_on: Date.current,
        allocations: { @payments[0].id => "30.000,00", @payments[1].id => "", @payments[2].id => "  " }
      }
    end

    remittance = Remittance.order(:created_at).last
    assert_equal 3_000_000, remittance.amount_cents
    assert_equal [ @payments[0].id ], remittance.remittance_allocations.pluck(:customer_payment_id)
    assert_equal 0, @payments[0].reload.pending_remittance_cents
    assert_equal 2_000_000, @payments[1].reload.pending_remittance_cents
    assert_equal 1_500_000, @payments[2].reload.pending_remittance_cents
  end

  test "all blank amounts leave financial records unchanged" do
    assert_no_difference([ "Remittance.count", "RemittanceAllocation.count" ]) do
      post remittances_path, params: {
        method: "cash", allocations: { @payments[0].id => "", @payments[1].id => "", @payments[2].id => "" }
      }
    end

    assert_redirected_to remittances_path
    follow_redirect!
    assert_includes response.body, "Seleccioná al menos un cobro con un importe válido"
  end

  test "negative invalid and excessive amounts are rejected with clear messages" do
    assert_no_difference("Remittance.count") do
      post remittances_path, params: { method: "cash", allocations: { @payments[0].id => "-1" } }
    end
    follow_redirect!
    assert_includes response.body, "deben ser mayores a cero"

    assert_no_difference("Remittance.count") do
      post remittances_path, params: { method: "cash", allocations: { @payments[0].id => "no-es-dinero" } }
    end
    follow_redirect!
    assert_includes response.body, "Ingresá un importe válido en pesos"

    assert_no_difference("Remittance.count") do
      post remittances_path, params: { method: "cash", allocations: { @payments[0].id => "30.000,01" } }
    end
    follow_redirect!
    assert_includes response.body, "supera el saldo disponible"
  end

  private

  def create_payment(amount_cents)
    reservation = @company.reservations.create!(departure_offer: @trip[:offer], seller_membership: @membership,
      created_by: @user, code: "R-#{SecureRandom.hex(3)}", channel: "reseller", status: "confirmed")
    reservation.customer_payments.create!(company: @company, recorded_by: @user,
      received_by_membership: @membership, amount_cents:, method: "cash", received_on: Date.current)
  end
end
