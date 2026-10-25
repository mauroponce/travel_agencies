require "test_helper"

class DockerBuildSafetyTest < ActiveSupport::TestCase
  test "Docker context excludes environment secrets including nested files" do
    patterns = Rails.root.join(".dockerignore").read.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    %w[.env .env.production .env.staging .env.local config/.env.production deploy/.env.staging].each do |path|
      ignored = false
      patterns.each do |pattern|
        negated = pattern.start_with?("!")
        glob = pattern.delete_prefix("!").delete_prefix("/")
        matched = File.fnmatch?(glob, path, File::FNM_PATHNAME | File::FNM_DOTMATCH)
        ignored = !negated if matched
      end
      assert ignored, "#{path} would be included in Docker build context"
    end
    assert_includes patterns, "config/master.key"
  end
end
