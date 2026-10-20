require "test_helper"

class AccessControlTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @company = Company.create!(name: "Empresa Uno", slug: "uno-#{SecureRandom.hex(3)}")
    @membership = create_membership(company: @company, user: @user, roles: %w[reseller])
    @trip = create_trip(company: @company)
    @other_company = Company.create!(name: "Empresa Dos", slug: "dos-#{SecureRandom.hex(3)}")
    @other_admin = create_membership(company: @other_company, user: create_user, roles: %w[admin])
    other_trip = create_trip(company: @other_company)
    @other_reservation = @other_company.reservations.create!(departure_offer: other_trip[:offer], created_by: @other_admin.user,
      code: "OTRA-#{SecureRandom.hex(2)}", channel: "direct", status: "requested")
    login_as(@user)
  end

  test "tenant identifiers cannot expose another company reservation" do
    get reservation_path(@other_reservation)
    assert_response :not_found

    post confirm_reservation_path(@other_reservation), params: {
      payment: { amount_cents: "500.00", method: "cash", received_on: Date.current }
    }
    assert_response :not_found
    assert_equal "requested", @other_reservation.reload.status
  end

  test "profile switch cannot elevate permissions" do
    post context_path, params: { role: "admin" }
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

  test "suspended companies cannot keep operating through an existing session or public links" do
    @company.update!(status: "suspended")

    get dashboard_path
    assert_response :not_found

    get public_trip_path(@trip[:offer].slug)
    assert_response :not_found
  end

  test "reseller cannot see non published offers" do
    hidden = create_trip(company: @company)[:offer]
    hidden.update!(status: "draft")

    get departure_offers_path
    assert_response :success
    assert_not_includes response.body, hidden.travel_package.name

    get departure_offer_path(hidden)
    assert_response :not_found
  end

  test "notification read action is scoped to the selected company" do
    second_membership = create_membership(company: @other_company, user: @user, roles: %w[reseller])
    notification = Notification.create!(company: @other_company, user: @user, event_type: "test",
      title: "Privada", body: "Otra empresa", deduplication_key: SecureRandom.uuid)

    patch notification_path(notification)
    assert_response :not_found
    assert_nil notification.reload.read_at
    assert second_membership.active?
  end

  test "opening a notification requires its tenant hostname" do
    create_membership(company: @other_company, user: @user, roles: %w[reseller])
    notification = Notification.create!(company: @other_company, user: @user, event_type: "test",
      title: "Cambio seguro", body: "Otra empresa", action_url: dashboard_path,
      deduplication_key: SecureRandom.uuid)

    get open_notification_path(notification)
    assert_response :not_found
    assert_nil notification.reload.read_at

    host! @other_company.platform_domain.hostname
    get "/test/sign-in", params: { email: @user.email, role: "reseller" }
    get open_notification_path(notification)
    assert_redirected_to dashboard_path
    assert notification.reload.read_at
  end

  test "agency admin changes only the membership commercial contact" do
    admin_user = create_user
    admin_membership = create_membership(company: @company, user: admin_user, roles: %w[admin])
    @user.update!(phone: "5491100000000")

    login_as(admin_user)
    patch team_member_path(@membership), params: { membership: { commercial_phone: "5491199999999" } }

    assert_redirected_to team_members_path
    assert_equal "5491199999999", @membership.reload.commercial_phone
    assert_equal "5491100000000", @user.reload.phone
    assert admin_membership.role?("admin")
  end

  test "public reseller contact comes from the membership for that company" do
    @membership.update!(commercial_phone: "5491188887777")
    @user.update!(phone: "5491100000000")

    get public_trip_path(@trip[:offer].slug, ref: @membership.reseller_authorization.public_code)

    assert_response :success
    assert_select "a[href^='https://wa.me/5491188887777?']"
    assert_not_includes response.body, "5491100000000"
  end

  test "reseller dashboard financial metrics exclude another reseller" do
    own = @company.remittances.create!(reseller_membership: @membership, declared_by: @user,
      code: "OWN-#{SecureRandom.hex(2)}", amount_cents: 12_345, method: "cash", status: "declared",
      declared_on: Date.current)
    another = create_membership(company: @company, user: create_user, roles: %w[reseller])
    hidden = @company.remittances.create!(reseller_membership: another, declared_by: another.user,
      code: "HIDDEN-#{SecureRandom.hex(2)}", amount_cents: 98_765, method: "cash", status: "declared",
      declared_on: Date.current)

    get dashboard_path

    assert_response :success
    assert_includes response.body, MoneyFormatter.call(own.amount_cents)
    assert_not_includes response.body, MoneyFormatter.call(hidden.amount_cents)
  end

  test "proof downloads require access to the remittance tenant and reseller scope" do
    second_membership = create_membership(company: @other_company, user: @user, roles: %w[reseller])
    remittance = @other_company.remittances.create!(reseller_membership: second_membership, declared_by: @user,
      code: "PROOF-#{SecureRandom.hex(2)}", amount_cents: 10_000, method: "transfer", declared_on: Date.current)
    remittance.proof.attach(io: StringIO.new("private proof"), filename: "proof.pdf", content_type: "application/pdf")

    get proof_remittance_path(remittance)

    assert_response :not_found
    assert_not_includes response.body, "private proof"
  end

  test "agency roles never grant platform access" do
    get platform_companies_path
    assert_response :not_found
  end

  test "global operator without an agency can suspend a company" do
    operator = create_user
    operator.platform_roles.create!(role: "operator")

    login_as(operator)
    assert_redirected_to platform_companies_path
    patch platform_company_path(@company), params: { company: { status: "suspended" } }

    assert_redirected_to platform_companies_path
    assert_equal "suspended", @company.reload.status
    assert AuditEvent.exists?(company: @company, actor: operator, action: "company.status_changed")
  end
end
