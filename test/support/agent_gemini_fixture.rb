module AgentGeminiFixture
  def self.trip(title, destination)
    Agent::AiContract.trip_properties.keys.index_with { nil }.merge(
      "title" => title, "destination" => destination, "supplier_name" => "Operador del flyer",
      "departs_on" => 2.months.from_now.to_date.iso8601, "returns_on" => (2.months.from_now + 4.days).to_date.iso8601,
      "duration_days" => 5, "price_cents" => 50_000_000, "currency" => "ARS", "price_unit" => "per_person",
      "hotel" => "Hotel de prueba", "meal_plan" => "Pensión completa", "transport" => "Micro",
      "included_services" => "Traslados y alojamiento", "warnings" => [], "evidence" => [])
  end

  def self.response(request)
    payload = JSON.parse(request.body)
    imported = payload["contents"].first["parts"].any? { |part| part.key?("inlineData") }
    data = if imported
      { trips: [ trip("Córdoba desde un flyer", "Córdoba"), trip("Mendoza desde un flyer", "Mendoza") ] }
    else
      { filters: Agent::AiContract.search_properties.keys.index_with { nil }.merge("destination" => "Córdoba", "max_price" => "600000", "currency" => "ARS", "price_unit" => "per_person"), interpretation: [ "Presupuesto por persona en ARS" ] }
    end
    { status: 200, body: { candidates: [ { finishReason: "STOP", content: { parts: [ { text: data.to_json } ] } } ], usageMetadata: { totalTokenCount: 30 } }.to_json, headers: { "Content-Type" => "application/json" } }
  end
end
