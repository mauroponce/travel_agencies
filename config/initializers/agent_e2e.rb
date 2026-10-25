# Browser acceptance only: production and staging can never enable these fixtures.
if Rails.env.test? && ENV["AGENT_E2E_FIXTURES"] == "true"
  Rails.application.config.after_initialize do
    require "webmock"
    require Rails.root.join("test/support/agent_gemini_fixture")
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
    WebMock::API.stub_request(:post, %r{https://generativelanguage.googleapis.com/v1beta/models/.+:generateContent})
      .to_return { |request| AgentGeminiFixture.response(request) }
    AgentAiJob.queue_adapter = :inline
  end
end
