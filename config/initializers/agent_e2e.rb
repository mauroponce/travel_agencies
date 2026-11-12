# Browser acceptance only: production and staging can never enable these fixtures.
if Rails.env.test? && ENV["AGENT_E2E_FIXTURES"] == "true"
  Rails.application.config.after_initialize do
    require "webmock"
    require Rails.root.join("test/support/agent_gemini_fixture")
    require Rails.root.join("test/support/e2e_pro_lifecycle_controller")
    require Rails.root.join("test/support/e2e_google_session_mock")
    OmniAuth::Strategies::GoogleOauth2.prepend(E2eGoogleSessionMock)
    ENV["PLATFORM_ADMIN_GOOGLE_EMAILS"] = [ ENV["PLATFORM_ADMIN_GOOGLE_EMAILS"], "e2e-operator@example.test" ].compact.join(",")
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "e2e-placeholder")
    OmniAuth.config.before_callback_phase = lambda do |env|
      if (id = env["rack.session"][:e2e_google_user_id])
        user = User.find(id)
        env["omniauth.auth"] = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: user.google_sub,
          info: { email: user.email, name: user.name }, extra: { id_info: { email_verified: true } })
      end
    end
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
    WebMock::API.stub_request(:post, %r{https://generativelanguage.googleapis.com/v1beta/models/.+:generateContent})
      .to_return { |request| AgentGeminiFixture.response(request) }
    AgentAiJob.queue_adapter = :inline
  end
end
