class DemoProvisioner
  def self.call(user = nil)
    raise "Demo provisioning is disabled in production" if Rails.env.production? && ENV["ENABLE_DEMO_DATA"] != "true"
    new(user).call
  end

  def initialize(user)
    @user = user || User.find_or_create_by!(google_sub: "demo-bootstrap") do |record|
      record.email = "demo@turistack.local"
      record.name = "Carolina Administradora"
    end
  end

  def call
    ApplicationRecord.transaction do
      company = Company.find_or_create_by!(slug: "sanzo-viajes") do |record|
        record.name = "Sanzó Viajes"
        record.email = "hola@sanzo.example"
        record.whatsapp = "5491150001234"
      end
      membership = company.memberships.find_or_create_by!(user: @user) { |record| record.status = "active" }
      membership.update!(commercial_phone: "5491155550101") if membership.commercial_phone.blank?
      MembershipRole::ROLES.each { |role| membership.membership_roles.find_or_create_by!(role:) }
      membership.create_reseller_authorization!(auto_confirm_enabled: true) unless membership.reseller_authorization
      @user.update!(phone: "5491155550101") if @user.phone.blank?
      build_catalog(company, membership) unless company.departures.exists?
      people = build_demo_people(company)
      ensure_demo_operations(company, membership, people)
      company
    end
  end

  private

  def build_demo_people(company)
    [
      [ "demo-revendedora-lucia", "lucia.revendedora@turistack.local", "Lucía Fernández", "5491155550202", [ "reseller" ] ],
      [ "demo-revendedor-juan", "juan.revendedor@turistack.local", "Juan Acosta", "5491155550303", [ "reseller" ] ],
      [ "demo-coordinador-martin", "martin.coordinador@turistack.local", "Martín Sosa", "5491155550404", [ "coordinator" ] ]
    ].to_h do |google_sub, email, name, phone, roles|
      user = User.find_or_create_by!(google_sub:) { |record| record.assign_attributes(email:, name:, phone:) }
      membership = company.memberships.find_or_create_by!(user:) { |record| record.status = "active" }
      membership.update!(commercial_phone: phone) if membership.commercial_phone.blank?
      roles.each { |role| membership.membership_roles.find_or_create_by!(role:) }
      membership.create_reseller_authorization!(auto_confirm_enabled: true) if roles.include?("reseller") && membership.reseller_authorization.nil?
      [ roles.first, membership ]
    end
  end

  def ensure_demo_operations(company, membership, people)
    departure = company.departures.order(:departs_at).first
    coordinator = people.fetch("coordinator")
    departure.departure_assignments.find_or_create_by!(membership: coordinator)
    rule = company.commission_rules.find_or_create_by!(reseller_membership: membership, status: "active") do |record|
      record.kind = "percentage"
      record.percentage = 10
    end
    reservation = company.reservations.find_by(code: "TS-DEMO-1048")
    if reservation && reservation.commission_entry.nil?
      CommissionEntry.create!(company:, reservation:, reseller_membership: membership,
        amount_cents: rule.calculate(reservation.total_cents), calculation_kind: rule.kind,
        rule_snapshot: { kind: rule.kind, percentage: rule.percentage }, status: "accrued")
    end
    payment = reservation&.customer_payments&.first
    return unless payment

    verified = company.remittances.find_or_create_by!(code: "RE-DEMO-VER") do |record|
      record.assign_attributes(reseller_membership: membership, declared_by: @user, verified_by: @user,
        amount_cents: 5_000_000, method: "transfer", status: "verified", declared_on: Date.current - 1,
        verified_at: Time.current, notes: "Transferencia demo verificada")
    end
    verified.remittance_allocations.find_or_create_by!(customer_payment: payment) { |item| item.amount_cents = 5_000_000 }
    pending = company.remittances.find_or_create_by!(code: "RE-DEMO-PEN") do |record|
      record.assign_attributes(reseller_membership: membership, declared_by: @user, amount_cents: 10_000_000,
        method: "cash", status: "declared", declared_on: Date.current, notes: "Efectivo entregado, pendiente de recepción")
    end
    pending.remittance_allocations.find_or_create_by!(customer_payment: payment) { |item| item.amount_cents = 10_000_000 }
    payment.update!(status: "partially_remitted")
  end

  def build_catalog(company, membership)
    destinations = %w[Mendoza Bariloche Córdoba].index_with do |name|
      company.destinations.create!(name:, province: name == "Bariloche" ? "Río Negro" : name)
    end
    mar_del_plata = company.destinations.create!(name: "Mar del Plata", province: "Buenos Aires")
    hotels = {
      geminis: company.accommodations.create!(destination: destinations["Mendoza"], name: "Hotel Géminis", category: "3 estrellas", address: "Mendoza Capital", maps_url: "https://maps.google.com"),
      aconcagua: company.accommodations.create!(destination: destinations["Mendoza"], name: "Hotel Aconcagua", category: "4 estrellas", address: "Mendoza Capital", maps_url: "https://maps.google.com"),
      lago: company.accommodations.create!(destination: destinations["Bariloche"], name: "Hotel Lago Azul", category: "3 estrellas", address: "Bariloche"),
      costa: company.accommodations.create!(destination: mar_del_plata, name: "Hotel Costa Sur", category: "3 estrellas", address: "Mar del Plata"),
      sierras: company.accommodations.create!(destination: destinations["Córdoba"], name: "Hotel Las Sierras", category: "3 estrellas", address: "Villa Carlos Paz")
    }
    bus = company.buses.create!(name: "SRM 01", registration: "AA 123 ZZ", capacity: 45, operator_name: "Transporte SRM")
    route = company.routes.create!(name: "Buenos Aires → Cuyo")
    points_data = [ [ "Terminal Varela", "Av. Calchaquí 686" ], [ "Rotonda Llavallol", "Ruta 205 y Camino de Cintura" ],
      [ "Terminal Del Piane", "Av. Perito Moreno 3950" ], [ "Terminal San Justo", "Av. Monseñor Bufano 3352" ],
      [ "Morón", "Av. Vergara y Acceso Oeste" ], [ "Moreno", "Acceso Oeste y Puente Gnecco" ],
      [ "Pacheco", "Panamericana 3058" ] ]
    points = points_data.map.with_index do |(name, address), index|
      point = company.boarding_points.create!(name:, address:)
      route.route_stages.create!(boarding_point: point, position: index + 1, kind: "boarding")
      point
    end
    departure = company.departures.create!(bus:, route:, code: "MZA-#{(Date.current + 14.days).strftime('%d%m')}",
      departs_at: 14.days.from_now.change(hour: 14, min: 30), returns_at: 20.days.from_now.change(hour: 8), capacity: 45, status: "open")
    points.each_with_index do |point, index|
      departure.departure_stops.create!(boarding_point: point, position: index + 1,
        scheduled_at: departure.departs_at + index.hours, published_name: point.name, published_address: point.address)
    end
    departure.departure_assignments.create!(membership:)

    package_sale = create_package(company, destinations["Mendoza"], "Mendoza Super Sale", 6, 3)
    package_comfort = create_package(company, destinations["Mendoza"], "Mendoza Confort", 6, 3)
    offer_sale = create_offer(company, package_sale, departure, hotels[:geminis], "mendoza-super-sale", 9_999_000, 1_000_000, "full", "SUPER SALE")
    create_offer(company, package_comfort, departure, hotels[:aconcagua], "mendoza-confort", 14_999_000, 5_000_000, "fixed", nil)

    [ [ destinations["Bariloche"], hotels[:lago], "Bariloche y sus lagos", "bariloche-lagos", 28_990_000 ],
      [ mar_del_plata, hotels[:costa], "Escapada a Mar del Plata", "mar-del-plata", 18_490_000 ],
      [ destinations["Córdoba"], hotels[:sierras], "Córdoba serrana", "cordoba-serrana", 21_500_000 ] ].each_with_index do |(destination, hotel, name, slug, price), index|
      other_bus = company.buses.create!(name: "SRM 0#{index + 2}", capacity: 45, operator_name: "Transporte SRM")
      other_departure = company.departures.create!(bus: other_bus, route:, code: "TS-#{index + 2}",
        departs_at: (28 + index * 14).days.from_now.change(hour: 15), capacity: 45, status: "open")
      points.each_with_index do |point, position|
        other_departure.departure_stops.create!(boarding_point: point, position: position + 1,
          scheduled_at: other_departure.departs_at + position.hours, published_name: point.name, published_address: point.address)
      end
      create_offer(company, create_package(company, destination, name, 6, 3), other_departure, hotel, slug, price, 7_000_000, "fixed", nil)
    end

    seed_reservation(company, membership, offer_sale)
  end

  def create_package(company, destination, name, days, nights)
    company.travel_packages.create!(destination:, name:, days:, nights:,
      description: "Una experiencia organizada para disfrutar #{destination.name} con comodidad y acompañamiento.",
      included_services: [ "Micro ida y vuelta", "Alojamiento", "Desayuno", "Coordinador permanente" ],
      excluded_services: [ "Excursiones opcionales" ],
      faqs: [ { question: "¿Cómo reservo?", answer: "Contactá a la empresa o a tu revendedor." } ])
  end

  def create_offer(company, package, departure, hotel, slug, price, deposit, type, promotion)
    offer = company.departure_offers.create!(travel_package: package, departure:, accommodation: hotel,
      slug:, status: "published", published_at: Time.current)
    offer.fare_versions.create!(price_cents: price, service_fee_cents: 1_000_000, deposit_type: type,
      deposit_cents: type == "full" ? price + 1_000_000 : deposit, promotion_label: promotion,
      valid_from: 1.day.ago, created_by: @user)
    offer
  end

  def seed_reservation(company, membership, offer)
    reservation = company.reservations.create!(departure_offer: offer, seller_membership: membership, created_by: @user,
      code: "TS-DEMO-1048", channel: "reseller", status: "confirmed", unit_price_cents: 9_999_000,
      unit_fee_cents: 1_000_000, minimum_payment_cents: 10_999_000, confirmed_at: 1.day.ago)
    2.times do |index|
      document = "3000000#{index}"
      passenger = reservation.passengers.create!(company:, departure_stop: offer.departure.departure_stops[index],
        accommodation: offer.accommodation, full_name: [ "Pablo Méndez", "Cecilia Méndez" ][index],
        document_number: document, document_last4: document.last(4), nationality: "Argentina", room_type: "Doble")
      company.seat_allocations.create!(departure: offer.departure, passenger:)
    end
    reservation.customer_payments.create!(company:, recorded_by: @user, received_by_membership: membership,
      amount_cents: 21_998_000, method: "mercado_pago", received_on: Date.current, notes: "Comprobante pendiente de rendición")
  end
end
