require "test_helper"
require_relative "../support_agent_data"

class AgentImportConcurrencyTest < ActiveSupport::TestCase
  include AgentTestData
  self.use_transactional_tests = false

  test "simultaneous confirmations create one set of drafts and revisions" do
    workspace = agent_workspace
    supplier = workspace.agent_suppliers.create!(name: "Carlos Sansot Viajes")
    task = workspace.agent_imports.create!(idempotency_key: SecureRandom.uuid, status: "completed", source: png_upload)
    [ 2, 8, 11, 14, 17, 25 ].each_with_index do |day, position|
      task.items.create!(agent_workspace: workspace, position:, extracted: {
        "title" => "Villa Carlos Paz", "destination" => "Villa Carlos Paz", "departs_on" => "2030-11-#{day.to_s.rjust(2, '0')}",
        "supplier_name" => "Carlos Sansot", "price_cents" => 10_500_000, "warnings" => [], "evidence" => {}
      })
    end
    results = concurrently(2) { Agent::SaveImport.call(import: AgentImport.find(task.id)).map(&:id).sort }
    assert_equal results.first, results.last
    assert_equal 6, workspace.agent_trips.count
    assert_equal 6, workspace.agent_trip_revisions.count
    assert_equal [ supplier.id ], workspace.agent_trip_revisions.pluck(:agent_supplier_id).uniq
    assert_equal 6, task.items.where.not(agent_trip_id: nil).count
    assert_equal 1, AuditEvent.where(agent_workspace: workspace, action: "agent_import.confirmed").count
  end

  test "simultaneous commercial name variants reuse one company" do
    workspace = agent_workspace
    names = [ "Cárlos   Sansót", "Carlos Sansot Viajes" ]
    results = concurrently(2) do |index|
      Agent::SupplierMatch.find_or_create!(workspace: AgentWorkspace.find(workspace.id), name: names[index]).id
    end
    assert_equal results.first, results.last
    assert_equal 1, workspace.agent_suppliers.count
  end

  private

  def concurrently(count)
    ready, start = Queue.new, Queue.new
    threads = count.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          yield index
        end
      end
    end
    count.times { ready.pop }
    count.times { start << true }
    threads.map(&:value)
  end
end
