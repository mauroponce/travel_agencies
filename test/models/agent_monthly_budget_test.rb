require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentMonthlyBudgetTest < ActiveSupport::TestCase
  include AgentTestData

  setup do
    @saved = ENV.to_h.slice("AGENT_PRO_MONTHLY_AI_UNITS", "GEMINI_API_KEY", "AGENT_MAX_PDF_PAGES")
    ENV["AGENT_PRO_MONTHLY_AI_UNITS"] = "2"
    ENV["GEMINI_API_KEY"] = "test-only"
    @workspace = agent_workspace
  end

  teardown do
    %w[AGENT_PRO_MONTHLY_AI_UNITS GEMINI_API_KEY AGENT_MAX_PDF_PAGES].each { |key| @saved.key?(key) ? ENV[key] = @saved[key] : ENV.delete(key) }
  end

  test "failures retries and request replays cannot evade the monthly provider budget" do
    task = Agent::AiRequests.create!(workspace: @workspace, kind: "import", attributes: { idempotency_key: "monthly", source: png_upload })
    request = stub_request(:post, %r{https://generativelanguage.googleapis.com/}).to_return(status: 503)
    3.times { AgentAiJob.perform_now("import", task.id) }
    assert_equal "monthly_limit", task.reload.error_code
    assert_equal 2, Agent::AiRequests.monthly_used(@workspace)
    assert_requested request, times: 2
    assert task.source.attached?
    assert_empty task.items
    assert_equal task, Agent::AiRequests.create!(workspace: @workspace, kind: "import", attributes: { idempotency_key: "monthly", source: png_upload })
    assert_raises(Agent::AiRequests::Limited) { Agent::AiRequests.retry_import!(task) }
    assert_raises(Agent::AiRequests::Limited) { Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { idempotency_key: "new", query: "Salta" }) }
    assert agent_trip(workspace: @workspace)
    assert Agent::AiRequests.create!(workspace: agent_workspace, kind: "search", attributes: { idempotency_key: "other", query: "Salta" })
  end

  test "monthly budget resets at local month boundary and every PDF page consumes a unit" do
    @workspace.agent_subscription.update!(trial_starts_at: Time.utc(2026, 10, 20), trial_ends_at: Time.utc(2026, 11, 10))
    travel_to Time.utc(2026, 11, 1, 2, 59) do
      task = @workspace.agent_searches.create!(idempotency_key: "last-month", query: "Salta")
      @workspace.agent_ai_executions.create!(agent_search: task, model: "test", contract_version: "test", status: "error", consumption_units: 2)
      assert_equal 0, Agent::AiRequests.monthly_remaining(@workspace)
    end
    travel_to Time.utc(2026, 11, 1, 3, 0) do
      assert_equal 2, Agent::AiRequests.monthly_remaining(@workspace)
      assert Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { idempotency_key: "new-month", query: "Salta" })
    end
    require "prawn"
    pdf = Prawn::Document.new
    2.times { pdf.start_new_page }
    Tempfile.create([ "three-pages", ".pdf" ]) do |file|
      file.binmode
      file.write(pdf.render)
      file.rewind
      assert_equal 3, Agent::UploadValidator.consumption_units(file)
      ENV["AGENT_MAX_PDF_PAGES"] = "2"
      assert_raises(Agent::UploadValidator::Invalid) { Agent::UploadValidator.call(file) }
    end
  end
  test "three page provider attempts charge three units and cannot fit in the remaining two" do
    ENV["AGENT_PRO_MONTHLY_AI_UNITS"] = "5"
    require "prawn"
    document = Prawn::Document.new
    2.times { document.start_new_page }
    Tempfile.create([ "budget-pages", ".pdf" ]) do |file|
      file.binmode
      file.write(document.render)
      file.rewind
      blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: "three.pdf", content_type: "application/pdf")
      task = Agent::AiRequests.create!(workspace: @workspace, kind: "import", attributes: { idempotency_key: "pdf-pages", source: blob })
      request = stub_gemini(trips: [ gemini_trip ])
      AgentAiJob.perform_now("import", task.id)
      assert_equal "completed", task.reload.status
      assert_equal 3, @workspace.agent_ai_executions.sole.consumption_units
      assert_equal 2, Agent::AiRequests.monthly_remaining(@workspace)
      assert_raises(Agent::AiRequests::Limited) do
        Agent::AiRequests.create!(workspace: @workspace, kind: "import", attributes: { idempotency_key: "second-pdf", source: blob })
      end
      assert_requested request, times: 1
      assert task.source.attached?
    end
  end
end
