require "test_helper"
require_relative "../support_agent_data"

class AgentPublicRedesignTest < ActionDispatch::IntegrationTest
  include AgentTestData

  test "public design renders six real cards pagination and contact on the canonical page and preview" do
    workspace = agent_workspace(show_about: true, about_text: "Mi historia personal")
    7.times { |index| agent_trip(workspace:, title: "Viaje #{index}").publish! }
    host! PlatformHosts.platform_host
    path = agent_site_path(agent_slug: workspace.slug)
    get path
    assert_response :success
    assert_select ".advisor-site .header .brand-name", text: /#{Regexp.escape(workspace.business_name)}/
    assert_select ".advisor-site .trip", count: 6
    assert_no_match(/translation missing/i, response.body)
    assert_select "a[rel=next]"
    assert_select ".trip [data-trip-id]", count: 6
    assert_select ".trip a.trip-cta[href^='https://wa.me/#{workspace.whatsapp}']", count: 6
    assert_select "#sobre-mi[hidden] .agent-about-text", text: "Mi historia personal"
    assert_select ".sidebar", count: 0
    get path, params: { page: 2 }
    assert_select ".advisor-site .trip", count: 1
    get path, params: { page: 999, destination: "Córdoba" }, headers: { "Turbo-Frame" => "public-catalog-results" }
    assert_select "turbo-frame#public-catalog-results .trip", count: 1
    assert_select ".chip", text: "Córdoba"
    get "/test/sign-in", params: { email: workspace.owner.email }
    get preview_agent_website_path
    assert_select ".advisor-site .trip", count: 6
    assert_select "form#public-catalog-filters[action=?]", preview_agent_website_path
  end

  test "a disabled catalog leaves an enabled public profile usable without a fake catalog" do
    workspace = agent_workspace(show_catalog: false, show_about: true, about_text: "Soy una persona real.")
    host! PlatformHosts.platform_host
    get agent_site_path(agent_slug: workspace.slug)
    assert_response :success
    assert_select "#viajes, #public-catalog-results", count: 0
    assert_select "#sobre-mi:not([hidden]) .agent-about-text", text: "Soy una persona real."
    assert_select ".header-nav a", text: "Viajes", count: 0
    assert_select ".profile-circle", text: workspace.public_name.split.filter_map(&:first).first(2).join.upcase
  end
end
