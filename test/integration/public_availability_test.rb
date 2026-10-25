require "test_helper"

class PublicAvailabilityTest < ActionDispatch::IntegrationTest
  test "public polling URL returns JSON reflecting new price and availability" do
    company = Company.create!(name: "Agencia", slug: "polling-agency")
    data = create_trip(company:)
    host! company.platform_domain.hostname
    get public_trip_path(data[:offer].slug)
    assert_response :success
    node = css_select("[data-availability-url-value]").first
    assert_equal public_trip_status_path(offer_slug: data[:offer].slug), node["data-availability-url-value"]
    get node["data-availability-url-value"], headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal data[:fare].price_cents, response.parsed_body["price_cents"]
    assert_equal 6, response.parsed_body["available_seats"]
    data[:fare].update!(price_cents: 200_000)
    data[:departure].update!(status: "cancelled")
    get node["data-availability-url-value"], headers: { "Accept" => "application/json" }
    assert_equal 200_000, response.parsed_body["price_cents"]
    assert_equal true, response.parsed_body["sold_out"]
  end
end
