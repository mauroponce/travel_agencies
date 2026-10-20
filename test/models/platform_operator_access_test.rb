require "test_helper"

class PlatformOperatorAccessTest < ActiveSupport::TestCase
  test "only configured emails retain the operator role" do
    allowed = create_user(email: "operator@turistack.test")
    denied = create_user(email: "otra-persona@turistack.test")
    denied.platform_roles.create!(role: "operator")

    PlatformOperatorAccess.synchronize!(allowed)
    PlatformOperatorAccess.synchronize!(denied)

    assert allowed.platform_operator?
    assert_not denied.platform_operator?
    assert_empty denied.platform_roles.reload
  end
end
