require "test_helper"

class RuntimeVersionTest < ActiveSupport::TestCase
  test "CI runtime and Docker use the same exact Ruby maintenance release" do
    version = Rails.root.join(".ruby-version").read.strip
    assert_equal version, RUBY_VERSION
    assert_match(/\A3\.4\.\d+\z/, version)
    assert_includes Rails.root.join("Dockerfile").read, "ARG RUBY_VERSION=#{version}\n"
  end
end
