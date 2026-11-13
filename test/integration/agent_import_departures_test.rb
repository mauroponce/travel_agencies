require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentImportDeparturesTest < ActionDispatch::IntegrationTest
  include AgentTestData

  test "four departures without a year remain distinguishable and selected drafts keep their flyer" do
    travel_to Time.zone.local(2026, 11, 3, 12)
    workspace = agent_workspace
    supplier = workspace.agent_suppliers.create!(name: "Carlos Sansot")
    task = workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload)
    Agent::Flyer.prepare_import!(task)
    departures = [ 3, 10, 17, 24 ].map do |day|
      { "label" => "#{day} de febrero", "departs_on" => nil, "returns_on" => nil }
    end
    data = Agent::AiContract.parse("import", { trips: [ gemini_trip(title: "Bombinhas", destination: "Bombinhas", departs_on: nil, departures:) ] }.to_json)
    task.update!(status: "completed")
    data["trips"].each_with_index { |extracted, position| task.items.create!(agent_workspace: workspace, position:, extracted:) }

    login_agent(workspace)
    get agent_trip_import_path(task)
    assert_response :success
    payload = response.parsed_body
    assert_equal %w[2027-02-03 2027-02-10 2027-02-17 2027-02-24], payload["items"].map { |item| item.dig("values", "departs_on") }
    assert_equal [ "3 de febrero", "10 de febrero", "17 de febrero", "24 de febrero" ], payload["items"].pluck("departure_text")
    assert_equal source_agent_trip_import_path(task), payload["source_url"]
    rows = payload["items"].each_with_index.map do |item, index|
      row = item.slice("id", "values", "selected", "overrides")
      row["selected"] = index < 2
      row["values"]["agent_supplier_id"] = supplier.id
      row["values"]["departs_on"] = [ "2030-02-03", "2030-02-10" ][index] if index < 2
      row
    end
    assert_difference "workspace.agent_trips.count", 2 do
      post confirm_agent_trip_import_path(task), params: { items: rows }, as: :json
      assert_response :success
    end
    first, second = task.items.order(:position).first(2)
    [ [ first, "2030-02-03" ], [ second, "2030-02-10" ] ].each do |item, date|
      assert_equal Date.iso8601(date), item.reload.agent_trip.current_revision.departs_on
      assert_equal task.source.blob, item.agent_trip.current_revision.flyer_source.blob
      assert_nil item.agent_trip.published_revision
    end
    assert_not_equal first.agent_trip_id, second.agent_trip_id
    assert_equal 2, task.items.where(agent_trip_id: nil).count
  end

  test "PDF wizard payload includes a private preview and original document" do
    workspace = agent_workspace
    task = workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, status: "completed",
      source: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/agent.pdf"), "application/pdf"))
    task.preview.attach(png_upload)
    task.items.create!(agent_workspace: workspace, position: 0, extracted: { "title" => "Viaje desde PDF" })
    login_agent(workspace)
    get agent_trip_import_path(task)
    assert_response :success
    assert_equal preview_agent_trip_import_path(task), response.parsed_body["preview_url"]
    assert_equal source_agent_trip_import_path(task), response.parsed_body["source_url"]
    get preview_agent_trip_import_path(task)
    assert_response :success
    assert_equal task.preview.download, response.body
    get source_agent_trip_import_path(task)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_equal task.source.download, response.body
  end

  test "previously extracted undated items show an assumed year without overwriting reviewed dates" do
    travel_to Time.zone.local(2026, 11, 3, 12)
    workspace = agent_workspace
    task = workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload, status: "completed")
    item = task.items.create!(agent_workspace: workspace, position: 0, extracted: {
      "title" => "Bombinhas", "destination" => "Bombinhas", "departure_text" => "3 de febrero", "departs_on" => nil
    })
    login_agent(workspace)
    get agent_trip_import_path(task)
    assert_equal "2027-02-03", response.parsed_body["items"].first.dig("values", "departs_on")
    assert_nil item.reload.extracted["departs_on"]

    item.update!(review_data: { "departs_on" => "2028-02-03" })
    get agent_trip_import_path(task)
    assert_equal "2028-02-03", response.parsed_body["items"].first.dig("values", "departs_on")
    item.update!(review_data: { "departs_on" => "" })
    get agent_trip_import_path(task)
    assert_equal "", response.parsed_body["items"].first.dig("values", "departs_on")
  end
end
