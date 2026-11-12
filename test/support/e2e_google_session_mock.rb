# Keep the normal Google redirect/CSP acceptance checks. Only browsers explicitly
# prepared by the lifecycle fixture receive a mocked callback, without changing
# global test mode between concurrent requests.
module E2eGoogleSessionMock
  def mock_request_call
    session[:e2e_google_user_id] ? super : request_call
  end

  def mock_callback_call
    session[:e2e_google_user_id] ? super : callback_call
  end
end
