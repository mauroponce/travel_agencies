ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

module TestData
  def create_user(name: "Persona Demo", email: nil)
    token = SecureRandom.hex(6)
    User.create!(google_sub: "google-#{token}", email: email || "#{token}@example.test", name:)
  end

  def create_membership(company:, user:, roles:, auto_confirm: true)
    membership = Membership.create!(company:, user:, status: "active")
    roles.each { |role| membership.membership_roles.create!(role:) }
    membership.create_reseller_authorization!(auto_confirm_enabled: auto_confirm) if roles.include?("reseller")
    membership
  end

  def create_trip(company:, capacity: 6, slug: nil)
    suffix = SecureRandom.hex(3)
    destination = company.destinations.create!(name: "Mendoza #{suffix}", province: "Mendoza")
    hotel = company.accommodations.create!(destination:, name: "Hotel #{suffix}", address: "Centro")
    bus = company.buses.create!(name: "Micro #{suffix}", capacity:)
    point = company.boarding_points.create!(name: "Terminal #{suffix}", address: "Calle 123")
    route = company.routes.create!(name: "Ruta #{suffix}")
    route.route_stages.create!(boarding_point: point, position: 1, kind: "boarding")
    departure = company.departures.create!(bus:, route:, code: "SAL-#{suffix}", departs_at: 10.days.from_now,
      returns_at: 15.days.from_now, capacity:, status: "open")
    stop = departure.departure_stops.create!(boarding_point: point, position: 1, scheduled_at: departure.departs_at,
      published_name: point.name, published_address: point.address)
    package = company.travel_packages.create!(destination:, name: "Mendoza #{suffix}", days: 6, nights: 3,
      description: "Viaje de prueba", included_services: [ "Micro" ], faqs: [])
    offer = company.departure_offers.create!(travel_package: package, departure:, accommodation: hotel,
      slug: slug || "oferta-#{suffix}", status: "published", published_at: Time.current)
    fare = offer.fare_versions.create!(price_cents: 100_000, service_fee_cents: 10_000, deposit_type: "fixed",
      deposit_cents: 50_000, valid_from: 1.hour.ago)
    { destination:, hotel:, bus:, point:, route:, departure:, stop:, package:, offer:, fare: }
  end

  def login_as(user)
    membership = user.memberships.active.includes(:company, :membership_roles).order(:created_at, :id).first
    if membership
      host! membership.company.platform_domain.hostname
      get "/test/sign-in", params: { email: user.email, role: membership.membership_roles.order(:created_at, :id).pick(:role) }
    else
      host! PlatformHosts.platform_host
      get "/test/sign-in", params: { email: user.email }
    end
  end
end

ActiveSupport::TestCase.include(TestData)
ActionDispatch::IntegrationTest.include(TestData)
