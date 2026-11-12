module Agent
  class AiRequests
    class Limited < StandardError; end
    def self.create!(workspace:, kind:, attributes:)
      workspace.with_lock do
        Access.new(workspace).require_commercial!
        model = kind == "import" ? AgentImport : AgentSearch
        existing = model.find_by(agent_workspace: workspace, idempotency_key: attributes.fetch(:idempotency_key))
        return existing if existing
        check_daily!(workspace:, kind:, include_requests: true)
        check_monthly!(workspace:, units: upload_units(attributes[:source]))
        limit = ENV.fetch(kind == "import" ? "AGENT_IMPORTS_PER_MINUTE" : "AGENT_SEARCHES_PER_MINUTE", kind == "import" ? 5 : 20).to_i.clamp(1, 1000)
        raise Limited, "Demasiadas solicitudes. Esperá un minuto antes de volver a intentar." if model.where(agent_workspace: workspace).where("created_at > ?", 1.minute.ago).count >= limit
        model.create!(attributes.merge(agent_workspace: workspace))
      end
    end

    def self.daily_limit(kind)
      ENV.fetch(kind == "import" ? "AGENT_IMPORTS_PER_DAY" : "AGENT_SEARCHES_PER_DAY", kind == "import" ? 25 : 100).to_i.clamp(1, 10000)
    end

    def self.monthly_used(workspace)
      month = Time.current.in_time_zone(workspace.timezone).all_month
      workspace.agent_ai_executions.where(created_at: month).sum(:consumption_units)
    end

    def self.monthly_remaining(workspace) = [ AgentSubscription.monthly_units - monthly_used(workspace), 0 ].max

    # Must share the workspace lock with execution creation. Errors and retries
    # retain their units; no asynchronous counter reset can reopen the budget.
    def self.check_monthly!(workspace:, units:)
      if monthly_used(workspace) + units > AgentSubscription.monthly_units
        raise Limited, "Agotaste el presupuesto mensual de IA. Se renueva el día 1 en la zona horaria de tu cuenta. Podés usar la carga y los filtros manuales."
      end
    end

    def self.upload_units(source)
      return 1 unless source
      if source.respond_to?(:open) && !source.respond_to?(:read)
        source.open { |io| UploadValidator.consumption_units(io) }
      else
        UploadValidator.consumption_units(source)
      end
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
        Access.new(task.agent_workspace).require_commercial!
        task.lock!
        return unless task.status == "error"
        check_daily!(workspace: task.agent_workspace, kind: "import")
        check_monthly!(workspace: task.agent_workspace, units: upload_units(task.source.attached? ? task.source.blob : nil))
        recent = task.agent_workspace.agent_ai_executions.where.not(agent_import_id: nil).where("created_at > ?", 1.minute.ago).count
        raise Limited, "Esperá un minuto antes de reintentar." if recent >= ENV.fetch("AGENT_IMPORTS_PER_MINUTE", 5).to_i.clamp(1, 1000)
        task.update!(status: "pending", error_code: nil, attempts: 0, processing_token: nil)
      end
    end
  end
end
