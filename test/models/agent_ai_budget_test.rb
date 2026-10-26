require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentAiBudgetTest < ActiveSupport::TestCase
  include AgentTestData
  include ActiveJob::TestHelper

  setup do
    @workspace = agent_workspace
    @saved_env = ENV.to_h.slice("AGENT_IMPORTS_PER_DAY", "AGENT_SEARCHES_PER_DAY", "GEMINI_API_KEY")
    ENV["GEMINI_API_KEY"] = "test-only"
    ENV["AGENT_IMPORTS_PER_DAY"] = ENV["AGENT_SEARCHES_PER_DAY"] = "2"
    clear_enqueued_jobs
  end

  teardown do
    %w[AGENT_IMPORTS_PER_DAY AGENT_SEARCHES_PER_DAY GEMINI_API_KEY].each { |key| @saved_env.key?(key) ? ENV[key] = @saved_env[key] : ENV.delete(key) }
  end

  test "daily requests are isolated by workspace and kind and replay is free" do
    task = Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { query: "Salta", idempotency_key: "first" })
    Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { query: "Salta", idempotency_key: "second" })
    assert_equal task, Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { query: "Salta", idempotency_key: "first" })
    assert_raises(Agent::AiRequests::Limited) { Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { query: "Salta", idempotency_key: "third" }) }
    assert Agent::AiRequests.create!(workspace: @workspace, kind: "import", attributes: { idempotency_key: "import" })
    assert Agent::AiRequests.create!(workspace: agent_workspace, kind: "search", attributes: { query: "Salta", idempotency_key: "other" })
  end

  test "automatic and manual retries cannot bypass daily provider budget" do
    task = @workspace.agent_imports.create!(idempotency_key: "retry", source: png_upload)
    request = stub_request(:post, %r{https://generativelanguage.googleapis.com/}).to_return(status: 503)
    3.times { AgentAiJob.perform_now("import", task.id) }
    assert_equal "error", task.reload.status
    assert_equal "daily_limit", task.error_code
    assert_equal 2, task.attempts
    assert_equal 2, @workspace.agent_ai_executions.count
    assert_requested request, times: 2
    assert_raises(Agent::AiRequests::Limited) { Agent::AiRequests.retry_import!(task) }
    assert task.source.attached?
    assert_empty task.items
  end

  test "daily budget resets at workspace midnight rather than UTC midnight" do
    # Buenos Aires midnight is 03:00 UTC.
    travel_to Time.utc(2026, 10, 26, 2, 59, 0) do
      2.times { |i| Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { query: "Salta", idempotency_key: i.to_s }) }
    end
    travel_to Time.utc(2026, 10, 26, 3, 0, 0) do
      assert Agent::AiRequests.create!(workspace: @workspace, kind: "search", attributes: { query: "Salta", idempotency_key: "new-day" })
    end
  end

  test "invalid structured response still records provider token usage" do
    task = @workspace.agent_searches.create!(idempotency_key: "bad-contract", query: "Salta")
    stub_gemini(filters: { "invalid" => true }, interpretation: [])
    AgentAiJob.perform_now("search", task.id)
    assert_equal "invalid_response", task.reload.error_code
    execution = @workspace.agent_ai_executions.last
    assert_equal "error", execution.status
    assert_equal 30, execution.usage["totalTokenCount"]
  end

  test "manual retry next day retains request identity source and human corrections" do
    task = @workspace.agent_imports.create!(idempotency_key: "same", source: png_upload, status: "error", attempts: 3)
    item = task.items.create!(agent_workspace: @workspace, position: 0, extracted: {}, review_data: { "title" => "Corregido" })
    blob_id = task.source.blob_id
    Agent::AiRequests.retry_import!(task)
    assert_equal "pending", task.reload.status
    assert_equal "same", task.idempotency_key
    assert_equal blob_id, task.source.blob_id
    assert_equal "Corregido", item.reload.review_data["title"]
  end
end
