require "test_helper"

class AccessControlTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @company = Company.create!(name: "Empresa Uno", slug: "uno-#{SecureRandom.hex(3)}")
    @membership = create_membership(company: @company, user: @user, roles: %w[reseller])
    @trip = create_trip(company: @company)
    @other_company = Company.create!(name: "Empresa Dos", slug: "dos-#{SecureRandom.hex(3)}")
    other_admin = create_membership(company: @other_company, user: create_user, roles: %w[admin])
    other_trip = create_trip(company: @other_company)
    @other_reservation = @other_company.reservations.create!(departure_offer: other_trip[:offer], created_by: other_admin.user,
      code: "OTRA-#{SecureRandom.hex(2)}", channel: "direct", status: "confirmed")
    login_as(@user)
  end

  test "tenant identifiers cannot expose another company reservation" do
    get reservation_path(@other_reservation)
    assert_response :not_found
  end

  test "profile switch cannot elevate permissions" do
    post context_path, params: { context_key: "#{@membership.id}:admin" }
    assert_response :forbidden
    get new_departure_offer_path
    assert_response :forbidden
  end

  test "reseller only sees own reservations" do
    another = create_membership(company: @company, user: create_user, roles: %w[reseller])
    hidden = @company.reservations.create!(departure_offer: @trip[:offer], seller_membership: another,
      created_by: another.user, code: "PRIV-#{SecureRandom.hex(2)}", channel: "reseller", status: "requested")
    get reservation_path(hidden)
    assert_response :not_found
  end
end
