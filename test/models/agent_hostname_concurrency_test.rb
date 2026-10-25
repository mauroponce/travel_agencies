require "test_helper"
require_relative "../support_agent_data"

class AgentHostnameConcurrencyTest < ActiveSupport::TestCase
  include AgentTestData
  self.use_transactional_tests = false

  test "simultaneous company and agent signup cannot claim the same hostname" do
    owner = create_user
    label = "race-#{SecureRandom.hex(5)}"
    ready, start = Queue.new, Queue.new
    operations = [
      -> { Company.create!(name: "Empresa concurrente", slug: label) },
      -> { agent_workspace(owner:, subdomain: label) }
    ]
    threads = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            operation.call
            :created
          rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
            :conflict
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [ :conflict, :created ], threads.map(&:value).sort
    assert_equal 1, HostnameRegistration.where(hostname: PlatformHosts.platform_hostname(label)).count
    assert_equal 1, Company.where(slug: label).count + AgentWorkspace.where(subdomain: label).count
  end
end
