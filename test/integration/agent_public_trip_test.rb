require "test_helper"
require_relative "../support_agent_data"

class AgentPublicTripTest < ActionDispatch::IntegrationTest
  include AgentTestData

  test "published trip presents commercial sections and the original flyer without exposing supplier notes" do
    workspace = agent_workspace(subdomain: nil, slug: "viajes-profesionales")
    supplier = workspace.agent_suppliers.create!(name: "Organizador del viaje", commercial_terms: "CONDICIÓN PRIVADA")
    trip = agent_trip(workspace:, supplier:, title: "Bombinhas · Playas de Mariscal", destination: "Bombinhas", region: "Brasil",
      departs_on: Date.new(2030, 2, 3), returns_on: Date.new(2030, 2, 13), duration_days: 10, duration_nights: 7,
      price_cents: 40_000, currency: "USD", price_basis: "Base cuádruple", hotel: "Residencial Flórida Premium",
      description: "Playas y descanso en Brasil.", included_services: "Transporte semi cama\nCoordinador", excluded_services: "Gastos de reserva",
      conditions: "USD 470 base triple; USD 695 base doble.", cover: png_upload)
    trip.publish!
    host! PlatformHosts.platform_host
    get agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)
    assert_response :success
    assert_select "h1", text: trip.published_revision.title
    assert_select ".travel-price", text: "USD 400,00"
    assert_select ".travel-booking-summary", text: /03\/02\/2030/
    assert_select ".travel-booking-summary", text: /13\/02\/2030/
    assert_select ".travel-booking-summary", text: /10 días \/ 7 noches/
    assert_select "a.travel-whatsapp[href^='https://wa.me/#{workspace.whatsapp}?text=']", count: 1
    assert_select "img.travel-flyer", count: 1
    assert_select "h2", text: "Conocé tu próximo viaje"
    assert_select ".travel-inclusions li", count: 3
    assert_select ".travel-conditions", text: /USD 470 base triple; USD 695 base doble/
    assert_select ".travel-organizer", text: /#{Regexp.escape(workspace.public_name)}/
    assert_not_includes response.body, supplier.name
    assert_select "meta[property='og:image']", count: 1
    assert_not_includes response.body, "CONDICIÓN PRIVADA"
  end

  test "a trip without a flyer or optional commercial data has an intentional fallback" do
    workspace = agent_workspace(subdomain: nil, slug: "viajes-sin-flyer")
    trip = agent_trip(workspace:)
    trip.publish!
    host! PlatformHosts.platform_host
    get agent_site_trip_path(agent_slug: workspace.slug, slug: trip.slug)
    assert_response :success
    assert_select ".travel-image-placeholder", count: 1
    assert_select "img.travel-flyer", count: 0
    assert_select "#travel-description-title", count: 0
    assert_select "#travel-services-title", count: 0
    assert_select ".travel-price", text: "ARS 500.000,00"
    assert_select "a.travel-whatsapp", count: 1
    assert_select ".travel-conditions", text: /Tarifas y disponibilidad sujetas a confirmación/
  end
end
