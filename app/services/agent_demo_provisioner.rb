class AgentDemoProvisioner
  def self.call
    raise "Agent demo data is local only" unless Rails.env.local?
    names = %w[agente agente-otro agente-nuevo-desktop-chromium agente-nuevo-mobile-chromium]
    names += %w[agente-buscador-desktop agente-buscador-mobile agente-web-desktop agente-web-mobile] if Rails.env.test? && ENV["AGENT_E2E_FIXTURES"] == "true"
    names.each do |name|
      user = User.find_or_create_by!(google_sub: "demo-#{name}") { |record| record.assign_attributes(email: "#{name}@turistack.local", name: name.titleize) }
      next if name.start_with?("agente-nuevo")
      workspace = user.agent_workspace || AgentWorkspace.create!(owner: user, business_name: "Viajes #{name.titleize}", public_name: user.name, whatsapp: "5491155550303", subdomain: name)
      supplier = workspace.agent_suppliers.find_or_create_by!(name: "Proveedor demo")
      next if workspace.agent_trips.exists?
      trip = Agent::SaveTrip.call(workspace:, attributes: { "agent_supplier_id" => supplier.id, "title" => "Escapada a Córdoba", "destination" => "Córdoba", "departs_on" => 2.months.from_now.to_date,
        "price_cents" => 50_000_000, "currency" => "ARS", "price_unit" => "per_person", "hotel" => "Hotel demo", "meal_plan" => "Pensión completa" })
      trip.publish!
    end
  end
end
