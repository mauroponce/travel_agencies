require "test_helper"
require "webmock/minitest"
require_relative "../support_agent_data"

class AgentAiBudgetConcurrencyTest < ActiveSupport::TestCase
  include AgentTestData
  self.use_transactional_tests = false

  test "simultaneous requests cannot exceed the last daily slot" do
    workspace = agent_workspace
    previous = ENV["AGENT_SEARCHES_PER_DAY"]
    ENV["AGENT_SEARCHES_PER_DAY"] = "1"
    ready, start = Queue.new, Queue.new
    threads = 2.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            Agent::AiRequests.create!(workspace: AgentWorkspace.find(workspace.id), kind: "search", attributes: { query: "Salta", idempotency_key: "race-#{i}" })
            :created
          rescue Agent::AiRequests::Limited
            :limited
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [ :created, :limited ], threads.map(&:value).sort
    assert_equal 1, workspace.agent_searches.count
  ensure
    previous ? ENV["AGENT_SEARCHES_PER_DAY"] = previous : ENV.delete("AGENT_SEARCHES_PER_DAY")
  end

  test "simultaneous jobs reserve at most the remaining provider attempt" do
    workspace = agent_workspace
    previous = ENV["AGENT_SEARCHES_PER_DAY"]
    ENV["AGENT_SEARCHES_PER_DAY"] = "1"
    tasks = 2.times.map { |i| workspace.agent_searches.create!(query: "Salta", idempotency_key: "job-#{i}") }
    request = stub_gemini(filters: Agent::AiContract.search_properties.keys.index_with { nil }, interpretation: [])
    ready, start = Queue.new, Queue.new
    threads = tasks.map do |task|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          AgentAiJob.perform_now("search", task.id)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:value)
    assert_equal %w[completed error], tasks.map { |task| task.reload.status }.sort
    assert_equal "daily_limit", tasks.find { |task| task.status == "error" }.error_code
    assert_equal 1, workspace.agent_ai_executions.count
    assert_requested request, times: 1
  ensure
    previous ? ENV["AGENT_SEARCHES_PER_DAY"] = previous : ENV.delete("AGENT_SEARCHES_PER_DAY")
  end
end
