require "test_helper"
require "webmock/minitest"
require "timeout"
require_relative "../support_agent_data"

class AgentExpiryConcurrencyTest < ActiveSupport::TestCase
  include AgentTestData
  self.use_transactional_tests = false

  setup do
    @previous_key = ENV["GEMINI_API_KEY"]
    ENV["GEMINI_API_KEY"] = "expiry-test-only"
  end

  teardown do
    @previous_key ? ENV["GEMINI_API_KEY"] = @previous_key : ENV.delete("GEMINI_API_KEY")
  end

  test "publication waiting for the workspace lock rechecks expired access" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    ready = Queue.new
    thread = nil
    workspace.with_lock do
      thread = Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          loaded = AgentTrip.find(trip.id)
          loaded.agent_workspace.agent_subscription # deliberately cache the active plan
          ready << true
          assert_raises(Pundit::NotAuthorizedError) { loaded.publish! }
        end
      end
      Timeout.timeout(10) { ready.pop }
      expire!(workspace)
    end
    thread.value
    assert_equal "draft", trip.reload.status
    assert_nil trip.published_revision_id
  ensure
    thread&.join(10)
  end

  test "expiry during an in-flight provider response discards results and consumes only its own attempt" do
    workspace = agent_workspace
    other = agent_workspace
    task = workspace.agent_imports.create!(source: png_upload, idempotency_key: SecureRandom.uuid)
    client = workspace.agent_clients.create!(name: "PRIVATE-NAME-NEVER-SEND", phone: "5491155559999", email: "never-send@example.test")
    client.notes.create!(agent_workspace: workspace, body: "PRIVATE-NOTE-NEVER-SEND")
    started, release = Queue.new, Queue.new
    request = stub_request(:post, %r{https://generativelanguage.googleapis.com/v1beta/models/.+:generateContent}).to_return do |sent|
      [ client.name, client.email, client.phone, client.notes.sole.body ].each { |secret| refute_includes sent.body, secret }
      started << true
      Timeout.timeout(10) { release.pop }
      { status: 200, body: gemini_response(trips: [ gemini_trip ]), headers: { "Content-Type" => "application/json" } }
    end
    thread = Thread.new do
      ApplicationRecord.connection_pool.with_connection { AgentAiJob.perform_now("import", task.id) }
    end
    Timeout.timeout(10) { started.pop }
    workspace.with_lock { expire!(workspace) }
    release << true
    thread.value
    assert_equal "plan_expired", task.reload.error_code
    assert_equal "error", task.status
    assert_empty task.items
    assert task.source.attached?
    assert_equal "discarded", workspace.agent_ai_executions.sole.status
    assert_equal 1, Agent::AiRequests.monthly_used(workspace)
    assert_equal 0, Agent::AiRequests.monthly_used(other)
    AgentAiJob.perform_now("import", task.id)
    assert_requested request, times: 1
  ensure
    release << true if release
    thread&.join(10)
  end

  test "a queued job rechecks expiry before reserving units or contacting the provider" do
    workspace = agent_workspace
    task = workspace.agent_searches.create!(query: "Salta", idempotency_key: SecureRandom.uuid)
    request = stub_gemini(filters: Agent::AiContract.search_properties.keys.index_with { nil }, interpretation: [])
    expire!(workspace)
    assert_no_difference "workspace.agent_ai_executions.count" do
      AgentAiJob.perform_now("search", task.id)
    end
    assert_equal "plan_expired", task.reload.error_code
    assert_not_requested request
  end

  private

  def expire!(workspace)
    workspace.agent_subscription.update!(trial_starts_at: 30.days.ago, trial_ends_at: 16.days.ago)
  end
end
