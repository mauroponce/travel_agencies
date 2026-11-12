require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentImportDeparturesTest < ActionDispatch::IntegrationTest
  include AgentTestData

  test "four departures without a year remain distinguishable and can be saved independently" do
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
    get agent_import_path(task)
    assert_response :success
    assert_select "h2", text: "Revisá las fichas extraídas"
    assert_select "p", text: "4 fichas extraídas. Cada salida se revisa y se guarda por separado."
    %w[03/02/2027 10/02/2027 17/02/2027 24/02/2027].each { |date| assert_select "p", text: "Bombinhas · #{date}" }
    assert_not_includes response.body, "Año a confirmar"
    assert_select "a", text: "Revisar ficha", count: 4

    first, second = task.items.order(:position).first(2)
    get edit_agent_import_item_path(task, first)
    assert_response :success
    assert_select "strong", text: "3 de febrero"
    assert_select "img.agent-source-image", count: 1
    assert_select "img.agent-source-image[src=?]", source_agent_import_path(task)
    assert_select "input#agent_trip_revision_departs_on[value='03/02/2027']"

    [ [ first, "2030-02-03" ], [ second, "2030-02-10" ] ].each do |item, date|
      assert_difference "workspace.agent_trips.count", 1 do
        patch agent_import_item_path(task, item), params: {
          commit_action: "draft", agent_trip_revision: { agent_supplier_id: supplier.id, title: "Bombinhas", destination: "Bombinhas", departs_on: date }
        }
        assert_response :redirect
      end
      assert_equal Date.iso8601(date), item.reload.agent_trip.current_revision.departs_on
      assert_equal task.source.blob, item.agent_trip.current_revision.flyer_source.blob
      assert_nil item.agent_trip.published_revision
    end
    assert_not_equal first.agent_trip_id, second.agent_trip_id
    assert_equal 2, task.items.where(agent_trip_id: nil).count
  end

  test "PDF review shows one preview and keeps the original document link" do
    workspace = agent_workspace
    task = workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid,
      source: Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/agent.pdf"), "application/pdf"))
    task.preview.attach(png_upload)
    item = task.items.create!(agent_workspace: workspace, position: 0, extracted: { "title" => "Viaje desde PDF" })
    login_agent(workspace)
    get edit_agent_import_item_path(task, item)
    assert_response :success
    assert_select "img.agent-source-image", count: 1
    assert_select "img.agent-source-image[src=?]", preview_agent_import_path(task)
    assert_select "a[href=?]", source_agent_import_path(task), text: "Abrir PDF original"
  end

  test "previously extracted undated items show an assumed year without overwriting reviewed dates" do
    travel_to Time.zone.local(2026, 11, 3, 12)
    workspace = agent_workspace
    task = workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload, status: "completed")
    item = task.items.create!(agent_workspace: workspace, position: 0, extracted: {
      "title" => "Bombinhas", "destination" => "Bombinhas", "departure_text" => "3 de febrero", "departs_on" => nil
    })
    login_agent(workspace)
    get agent_import_path(task)
    assert_select "p", text: "Bombinhas · 03/02/2027"
    assert_not_includes response.body, "Año a confirmar"
    get edit_agent_import_item_path(task, item)
    assert_select "input#agent_trip_revision_departs_on[value='03/02/2027']"
    assert_nil item.reload.extracted["departs_on"]

    item.update!(review_data: { "departs_on" => "2028-02-03" })
    get edit_agent_import_item_path(task, item)
    assert_select "input#agent_trip_revision_departs_on[value='03/02/2028']"
    item.update!(review_data: { "departs_on" => "" })
    get edit_agent_import_item_path(task, item)
    assert_select "input[name='agent_trip_revision[departs_on]']" do |inputs|
      assert inputs.all? { |input| input["value"].blank? }
    end
  end
end
