module Agent
  class AiRequests
    class Limited < StandardError; end
    def self.create!(workspace:, kind:, attributes:)
      workspace.with_lock do
        model = kind == "import" ? AgentImport : AgentSearch
        existing = model.find_by(agent_workspace: workspace, idempotency_key: attributes.fetch(:idempotency_key))
        return existing if existing
        limit = ENV.fetch(kind == "import" ? "AGENT_IMPORTS_PER_MINUTE" : "AGENT_SEARCHES_PER_MINUTE", kind == "import" ? 5 : 20).to_i.clamp(1, 1000)
        raise Limited, "Demasiadas solicitudes. Esperá un minuto antes de volver a intentar." if model.where(agent_workspace: workspace).where("created_at > ?", 1.minute.ago).count >= limit
        model.create!(attributes.merge(agent_workspace: workspace))
      end
    end
  end
end
