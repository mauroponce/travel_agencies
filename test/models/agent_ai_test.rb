require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentAiTest < ActiveSupport::TestCase
  include AgentTestData
  include ActiveJob::TestHelper

  setup do
    @workspace = agent_workspace
    @previous_key = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "test-api-key"
    clear_enqueued_jobs
  end
  teardown do
    @previous_key ? ENV["GEMINI_API_KEY"] = @previous_key : ENV.delete("GEMINI_API_KEY")
  end

  test "real image MIME and PDF parsing reject forged damaged and oversize files" do
    upload = png_upload
    assert_equal "image/png", Agent::UploadValidator.call(upload)
    file = Tempfile.new([ "valid", ".pdf" ])
    file.binmode
    file.write(Prawn::Document.new { text "Flyer de prueba" }.render)
    file.rewind
    assert_equal "application/pdf", Agent::UploadValidator.call(file)
    file.rewind
    file.truncate(0)
    file.write("%PDF-1.7 corrupt")
    file.rewind
    assert_raises(Agent::UploadValidator::Invalid) { Agent::UploadValidator.call(file) }
    file.truncate(11.megabytes)
    assert_raises(Agent::UploadValidator::Invalid) { Agent::UploadValidator.call(file) }
    forged = Rack::Test::UploadedFile.new(upload.path, "application/pdf")
    assert_raises(Agent::UploadValidator::Invalid) { Agent::UploadValidator.call(forged) }
  ensure
    file&.close!
  end

  test "provider schema omits incompatible maxItems while local contract enforces it" do
    provider = Agent::AiContract.provider_schema("import")
    assert_nil provider[:properties][:trips][:maxItems]
    assert_equal 50, Agent::AiContract.schema("import")[:properties][:trips][:maxItems]
    assert_raises(Agent::AiContract::Invalid) { Agent::AiContract.parse("import", { trips: Array.new(51) { gemini_trip } }.to_json) }
  end

  test "concurrency limit postpones work without consuming an attempt" do
    2.times do
      @workspace.agent_searches.create!(idempotency_key: SecureRandom.uuid, query: "En curso", status: "processing", started_at: Time.current)
    end
    task = @workspace.agent_searches.create!(idempotency_key: SecureRandom.uuid, query: "Pendiente")
    assert_enqueued_with(job: AgentAiJob) { AgentAiJob.perform_now("search", task.id) }
    assert_equal "pending", task.reload.status
    assert_equal 0, task.attempts
    assert_not_requested :post, %r{https://generativelanguage.googleapis.com/}
  end

  test "stale provider response cannot overwrite a task reclaimed by recovery" do
    task = @workspace.agent_searches.create!(idempotency_key: SecureRandom.uuid, query: "Córdoba")
    filters = Agent::AiContract.search_properties.keys.index_with { nil }
    stub_request(:post, %r{https://generativelanguage.googleapis.com/}).to_return do
      task.reload.update!(processing_token: "new-owner", status: "pending")
      { status: 200, body: gemini_response(filters:, interpretation: []), headers: { "Content-Type" => "application/json" } }
    end
    AgentAiJob.perform_now("search", task.id)
    assert_equal "pending", task.reload.status
    assert_equal "discarded", @workspace.agent_ai_executions.last.status
    assert_empty task.filters
  end

  test "relative search context contains workspace date and timezone" do
    task = @workspace.agent_searches.new(query: "enero", idempotency_key: "context")
    travel_to(Time.zone.local(2026, 10, 25, 23, 59)) do
      prompt = Agent::GeminiClient.prompt("search", task)
      assert_includes prompt, "2026-10-25"
      assert_includes prompt, @workspace.timezone
      assert_includes prompt, "próxima ocurrencia futura"
    end
  end

  test "structured extraction creates several candidates and a replay does not duplicate them" do
    task = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload)
    request = stub_gemini(trips: [ gemini_trip, gemini_trip(title: "Otro viaje") ])
    AgentAiJob.perform_now("import", task.id)
    assert_equal "completed", task.reload.status
    assert_equal 2, task.items.count
    assert_equal 30, task.agent_workspace.agent_ai_executions.last.usage["totalTokenCount"]
    AgentAiJob.perform_now("import", task.id)
    assert_equal 2, task.items.count
    assert_requested request, times: 1
    assert_empty @workspace.agent_trips
  end

  test "PDF import uses the same validated extraction contract" do
    task = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid)
    task.source.attach(io: StringIO.new(Prawn::Document.new { text "Córdoba" }.render), filename: "flyer.pdf", content_type: "application/pdf")
    stub_gemini(trips: [ gemini_trip ])
    AgentAiJob.perform_now("import", task.id)
    assert_equal "completed", task.reload.status
  end

  test "missing commercial fields remain null and arbitrary keys are rejected" do
    data = Agent::AiContract.parse("import", { trips: [ gemini_trip(price_cents: nil, hotel: nil) ] }.to_json)
    assert_nil data["trips"].first["price_cents"]
    assert_nil data["trips"].first["hotel"]
    assert_raises(Agent::AiContract::Invalid) { Agent::AiContract.parse("import", { trips: [ gemini_trip(injected: "SQL") ] }.to_json) }
    assert_raises(Agent::AiContract::Invalid) { Agent::AiContract.parse("import", "not json") }
    assert_raises(Agent::AiContract::Invalid) { Agent::AiContract.parse("import", { trips: [ gemini_trip(price_cents: "500") ] }.to_json) }
  end

  test "bad provider JSON is a processing error and never publishes a trip" do
    task = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, source: png_upload)
    stub_request(:post, %r{https://generativelanguage.googleapis.com/}).to_return(status: 200, body: "invalid json")
    AgentAiJob.perform_now("import", task.id)
    assert_equal "error", task.reload.status
    assert_equal "invalid_response", task.error_code
    assert_empty task.items
    assert_empty @workspace.agent_trips
  end

  test "transient provider failures retry at most three attempts" do
    task = @workspace.agent_searches.create!(idempotency_key: SecureRandom.uuid, query: "Córdoba")
    stub_request(:post, %r{https://generativelanguage.googleapis.com/}).to_return(status: 503, body: "unavailable")
    3.times { AgentAiJob.perform_now("search", task.id) }
    assert_equal "error", task.reload.status
    assert_equal 3, task.attempts
    assert_equal "provider_503", task.error_code
    assert_equal 3, @workspace.agent_ai_executions.count
  end

  test "search executes validated filters on authorized PostgreSQL records only" do
    cheap = agent_trip(workspace: @workspace)
    agent_trip(workspace: @workspace, price_cents: 90_000_000)
    agent_trip(workspace: agent_workspace)
    filters = Agent::AiContract.search_properties.keys.index_with { nil }.merge("destination" => "Córdoba", "currency" => "ARS", "price_unit" => "per_person", "max_price" => "600000")
    stub_gemini(filters:, interpretation: [ "Presupuesto por persona en ARS" ])
    task = @workspace.agent_searches.create!(idempotency_key: SecureRandom.uuid, query: "Córdoba menos de $600000 por persona")
    AgentAiJob.perform_now("search", task.id)
    assert_equal "completed", task.reload.status
    assert_equal [ cheap.id ], Agent::CatalogQuery.call(workspace: @workspace, filters: task.filters).pluck(:id)
    assert_empty Agent::CatalogQuery.call(workspace: @workspace, filters: task.filters.merge("destination" => "No existe"))
  end

  test "import item confirmation is idempotent and workspace scoped" do
    task = @workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid)
    item = task.items.create!(agent_workspace: @workspace, position: 0, extracted: { "warnings" => [] })
    supplier = @workspace.agent_suppliers.create!(name: "Operador")
    attributes = { "agent_supplier_id" => supplier.id, "title" => "Borrador" }
    first = Agent::SaveTrip.call(workspace: @workspace, attributes:, item:)
    second = Agent::SaveTrip.call(workspace: @workspace, attributes:, item:)
    assert_equal first.id, second.id
    assert_equal 1, @workspace.agent_trips.count
  end

  test "rate limits and request identities are enforced inside workspace lock" do
    task = Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { idempotency_key: "same", query: "Córdoba" })
    assert_equal task.id, Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { idempotency_key: "same", query: "Otra" }).id
    19.times { |i| Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { idempotency_key: i.to_s, query: "Córdoba" }) }
    assert_raises(Agent::AiRequests::Limited) { Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { idempotency_key: "excess", query: "Córdoba" }) }
  end

  test "crashed processing is recovered and a suspended workspace never calls Gemini" do
    task = @workspace.agent_searches.create!(idempotency_key: SecureRandom.uuid, query: "Córdoba", status: "processing", processing_token: "old", attempts: 1, started_at: 10.minutes.ago)
    task.update_columns(updated_at: 10.minutes.ago)
    RecoverAgentAiJobsJob.perform_now
    assert_equal "pending", task.reload.status
    assert_nil task.processing_token
    @workspace.update!(status: "suspended")
    AgentAiJob.perform_now("search", task.id)
    assert_equal "pending", task.reload.status
    assert_not_requested :post, %r{https://generativelanguage.googleapis.com/}
  end
end
