class AgentAiJob < ApplicationJob
  queue_as :default
  TASKS = { "import" => "AgentImport", "search" => "AgentSearch" }.freeze
  LEASE = 5.minutes

  def perform(kind, id)
    task = TASKS.fetch(kind).constantize.find_by(id:)
    return unless task && AgentWorkspace.enabled?
    token = claim(task)
    return unless token
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    execution = task.agent_workspace.agent_ai_executions.create!(kind == "import" ? { agent_import: task, model: Agent::GeminiClient.model, contract_version: Agent::AiContract::VERSION, status: "processing" } : { agent_search: task, model: Agent::GeminiClient.model, contract_version: Agent::AiContract::VERSION, status: "processing" })
    Agent::Flyer.prepare_import!(task) if kind == "import"
    data, usage = Agent::GeminiClient.call(kind:, task:)
    task.agent_workspace.with_lock do
      task.lock!
      return execution.update!(status: "discarded", duration_ms: elapsed(started), usage:) unless task.processing_token == token && task.agent_workspace.active?
      if kind == "import"
        data.fetch("trips").each_with_index do |attributes, position|
          task.items.create!(agent_workspace: task.agent_workspace, position:, extracted: attributes)
        end
      else
        task.assign_attributes(filters: data.fetch("filters"), interpretation: data.fetch("interpretation"))
      end
      task.update!(status: "completed", processing_token: nil, error_code: nil)
      execution.update!(status: "completed", duration_ms: elapsed(started), usage:)
    end
  rescue Agent::GeminiClient::Failure => error
    finish_error(task, token, execution, started, error.code, error.transient)
  rescue Agent::UploadValidator::Invalid
    finish_error(task, token, execution, started, "invalid_file", false)
  rescue StandardError => error
    raise unless task && token
    Rails.logger.error({ event: "agent_ai.failed", task_id: task.id, exception_class: error.class.name }.to_json)
    finish_error(task, token, execution, started, "internal_error", false)
  end

  private

  def claim(task)
    task.agent_workspace.with_lock do
      task.lock!
      return unless task.agent_workspace.active? && task.status == "pending"
      running = [ AgentImport, AgentSearch ].sum { |model| model.where(agent_workspace: task.agent_workspace, status: "processing").where("started_at > ?", LEASE.ago).count }
      if running >= ENV.fetch("AGENT_AI_CONCURRENCY", 2).to_i.clamp(1, 10)
        self.class.set(wait: 5.seconds).perform_later(task.is_a?(AgentImport) ? "import" : "search", task.id)
        return
      end
      return task.update!(status: "error", error_code: "attempts_exhausted") && nil if task.attempts >= 3
      token = SecureRandom.uuid
      task.update!(status: "processing", processing_token: token, started_at: Time.current, attempts: task.attempts + 1)
      token
    end
  end

  def elapsed(started) = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

  def finish_error(task, token, execution, started, code, transient)
    retry_task = false
    task.with_lock do
      if task.processing_token == token
        retry_task = transient && task.attempts < 3 && task.agent_workspace.active?
        task.update!(status: retry_task ? "pending" : "error", error_code: code, processing_token: nil)
      end
      execution&.update!(status: "error", error_code: code, duration_ms: started && elapsed(started))
    end
    self.class.set(wait: (task.attempts * 10).seconds).perform_later(task.is_a?(AgentImport) ? "import" : "search", task.id) if retry_task
  end
end
