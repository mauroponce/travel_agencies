module AgentTestData
  def agent_workspace(owner: create_user, **attributes)
    AgentWorkspace.create!({ owner:, business_name: "Agente Demo", public_name: "Lucía", whatsapp: "5491155550101", subdomain: "agente-#{SecureRandom.hex(4)}" }.merge(attributes))
  end

  def agent_trip(workspace:, supplier: nil, **attributes)
    supplier ||= workspace.agent_suppliers.find_or_create_by!(name: "Proveedor")
    Agent::SaveTrip.call(workspace:, attributes: { "agent_supplier_id" => supplier.id, "title" => "Córdoba en verano", "destination" => "Córdoba", "departs_on" => 2.months.from_now.to_date, "returns_on" => (2.months.from_now + 4.days).to_date, "price_cents" => 50_000_000, "currency" => "ARS", "price_unit" => "per_person", "meal_plan" => "Pensión completa", "duration_days" => 5 }.merge(attributes.stringify_keys))
  end

  def login_agent(workspace)
    host! workspace.hostname || PlatformHosts.platform_host
    get "/test/sign-in", params: { email: workspace.owner.email }
  end

  def gemini_trip(**attributes)
    Agent::AiContract.trip_properties.keys.index_with { nil }.merge("title" => "Córdoba en verano", "destination" => "Córdoba", "departs_on" => 2.months.from_now.to_date.iso8601, "price_cents" => 50_000_000, "currency" => "ARS", "price_unit" => "per_person", "warnings" => [], "evidence" => []).merge(attributes.stringify_keys)
  end

  def gemini_response(data)
    { candidates: [ { finishReason: "STOP", content: { parts: [ { text: data.to_json } ] } } ], usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 20, totalTokenCount: 30 } }.to_json
  end

  def stub_gemini(data)
    stub_request(:post, %r{https://generativelanguage.googleapis.com/v1beta/models/.+:generateContent}).to_return(status: 200, body: gemini_response(data), headers: { "Content-Type" => "application/json" })
  end

  def png_upload
    Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/agent.png"), "image/png")
  end
end
