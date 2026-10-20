require "test_helper"

class BrandingTest < ActionDispatch::IntegrationTest
  test "platform landing uses the Turistack brand" do
    host! PlatformHosts.platform_host

    get root_path

    assert_response :success
    assert_select "title", text: "Turistack · Plataforma turística"
    assert_includes response.body, "Turistack"
    assert_not_includes response.body, "NexoViajes"
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
