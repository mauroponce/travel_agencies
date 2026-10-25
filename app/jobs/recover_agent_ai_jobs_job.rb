class RecoverAgentAiJobsJob < ApplicationJob
  queue_as :default
  def perform
    return unless AgentWorkspace.enabled?
    { AgentImport => "import", AgentSearch => "search" }.each do |model, kind|
      model.where(status: %w[pending processing]).where("updated_at < ?", 1.minute.ago).find_each do |task|
        enqueue = false
        task.with_lock do
          if task.status == "pending" || (task.status == "processing" && task.started_at < AgentAiJob::LEASE.ago)
            source_key = kind == "import" ? :agent_import_id : :agent_search_id
            task.agent_workspace.agent_ai_executions.where(source_key => task.id, status: "processing")
              .update_all(status: "discarded", error_code: "lease_expired", updated_at: Time.current)
            task.update!(status: task.attempts >= 3 ? "error" : "pending", processing_token: nil, error_code: task.attempts >= 3 ? "attempts_exhausted" : nil)
            enqueue = task.status == "pending" && task.agent_workspace.active?
          end
        end
        AgentAiJob.perform_later(kind, task.id) if enqueue
      end
    end
  end
end
