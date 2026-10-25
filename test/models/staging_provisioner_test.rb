require "test_helper"

class StagingProvisionerTest < ActiveSupport::TestCase
  test "refuses to provision shared demo data outside staging" do
    error = assert_raises(StagingProvisioner::UnsafeEnvironment) { StagingProvisioner.call }

    assert_includes error.message, "RAILS_ENV=staging"
  end
end
