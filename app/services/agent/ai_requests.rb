module Agent
  class AiRequests
    class Limited < StandardError; end
    def self.create!(workspace:, kind:, attributes:)
      workspace.with_lock do
        model = kind == "import" ? AgentImport : AgentSearch
        existing = model.find_by(agent_workspace: workspace, idempotency_key: attributes.fetch(:idempotency_key))
        return existing if existing
        check_daily!(workspace:, kind:, include_requests: true)
        limit = ENV.fetch(kind == "import" ? "AGENT_IMPORTS_PER_MINUTE" : "AGENT_SEARCHES_PER_MINUTE", kind == "import" ? 5 : 20).to_i.clamp(1, 1000)
        raise Limited, "Demasiadas solicitudes. Esperá un minuto antes de volver a intentar." if model.where(agent_workspace: workspace).where("created_at > ?", 1.minute.ago).count >= limit
        model.create!(attributes.merge(agent_workspace: workspace))
      end
    end

    def self.daily_limit(kind)
      ENV.fetch(kind == "import" ? "AGENT_IMPORTS_PER_DAY" : "AGENT_SEARCHES_PER_DAY", kind == "import" ? 25 : 100).to_i.clamp(1, 10000)
    end

    # Call under the workspace lock, including when reserving an execution.
    # Every provider attempt consumes this budget, even on manual/automatic retry.
    def self.check_daily!(workspace:, kind:, include_requests: false)
      day = Time.current.in_time_zone(workspace.timezone).all_day
      foreign_key = kind == "import" ? :agent_import_id : :agent_search_id
      used = workspace.agent_ai_executions.where.not(foreign_key => nil).where(created_at: day).count
      model = kind == "import" ? AgentImport : AgentSearch
      requested = include_requests && model.where(agent_workspace: workspace, created_at: day).count
      if used >= daily_limit(kind) || (requested && requested >= daily_limit(kind))
        raise Limited, "Alcanzaste el límite diario de IA para #{kind == 'import' ? 'importaciones' : 'búsquedas'}. Se renueva a medianoche de tu cuenta. Podés continuar con la carga y los filtros manuales."
      end
    end

    def self.retry_import!(task)
      task.agent_workspace.with_lock do
        task.lock!
        return unless task.status == "error"
        check_daily!(workspace: task.agent_workspace, kind: "import")
        recent = task.agent_workspace.agent_ai_executions.where.not(agent_import_id: nil).where("created_at > ?", 1.minute.ago).count
        raise Limited, "Esperá un minuto antes de reintentar." if recent >= ENV.fetch("AGENT_IMPORTS_PER_MINUTE", 5).to_i.clamp(1, 1000)
        task.update!(status: "pending", error_code: nil, attempts: 0, processing_token: nil)
      end
    end
  end
end
