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
    attachment = payload["contents"].first["parts"].find { |part| part.key?("inlineData") }
    digest = Digest::SHA256.hexdigest(Base64.decode64(attachment.dig("inlineData", "data"))) if attachment
    require Rails.root.join("test/support/agent_flyer_examples")
    data = if imported && digest == Digest::SHA256.file(Rails.root.join("test/fixtures/files/agent_sansot.jpeg")).hexdigest
      { trips: AgentFlyerExamples.multiple_bases }
    elsif imported && digest == Digest::SHA256.file(Rails.root.join("test/fixtures/files/agent_multi_program.jpg")).hexdigest
      { trips: AgentFlyerExamples.multiple_programs }
    elsif imported
      departures = [ 3, 10, 17, 24 ].map do |day|
        date = 2.months.from_now.to_date.change(day:)
        { "label" => date.strftime("%d/%m"), "departs_on" => nil, "returns_on" => nil }
      end
      { trips: [ trip("Córdoba desde un flyer", "Córdoba").merge("departs_on" => nil, "returns_on" => nil, "departures" => departures) ] }
    else
      { filters: Agent::AiContract.search_properties.keys.index_with { nil }.merge("destination" => "Córdoba", "max_price" => "600000", "currency" => "ARS", "price_unit" => "per_person"), interpretation: [ "Presupuesto por persona en ARS" ] }
    end
    { status: 200, body: { candidates: [ { finishReason: "STOP", content: { parts: [ { text: data.to_json } ] } } ], usageMetadata: { totalTokenCount: 30 } }.to_json, headers: { "Content-Type" => "application/json" } }
  end
end
