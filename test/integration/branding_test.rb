require "test_helper"

class BrandingTest < ActionDispatch::IntegrationTest
  test "platform landing uses the Turistack brand" do
    host! PlatformHosts.platform_host

    get root_path

    assert_response :success
    assert_select "title", text: "Turistack Pro · Tu negocio de viajes"
    assert_includes response.body, "Turistack"
    assert_not_includes response.body, "NexoViajes"
    assert_select "body.turistack-landing"
    assert_select "h1", text: /Tu marca, tus viajes,.*tus clientes\./
    assert_select "form[action=?][method=post], form[action=?][method=post]", auth_start_path, auth_start_path(purpose: "agent_onboarding"), count: 4
    assert_select "select[aria-label='Cambiar perfil de demostración'] option", count: 0
    assert_includes response.body, "Sin débito automático".downcase
    assert_not_includes response.body, "cobros y rendiciones"
    %w[features tour plan].each do |section|
      assert_select "section[id=?]", section
    end
  end

  test "new reservation codes use the Turistack prefix" do
    user = create_user
    company = Company.create!(name: "Agencia Marca", slug: "agencia-marca-#{SecureRandom.hex(3)}")
    membership = create_membership(company:, user:, roles: %w[admin])
    trip = create_trip(company:)

    reservation = Reservations::Confirm.call(
      offer: trip[:offer], actor: user, membership:, channel: "direct", idempotency_key: SecureRandom.uuid,
      passengers: [ { full_name: "Persona Prueba", document_number: "30111222", nationality: "Argentina",
        departure_stop_id: trip[:stop].id, room_type: "Doble" } ],
      payment: { amount_cents: 50_000, method: "cash", received_on: Date.current }
    )

    assert_match(/\ATS-\d{4}-[A-F0-9]{6}\z/, reservation.code)
  end
end
