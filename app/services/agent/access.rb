module Agent
  # Business entitlement is independent of identity and company memberships.
  class Access
    def initialize(workspace)
      @workspace = workspace
    end

    def read? = @workspace&.persisted? && AgentWorkspace.where(id: @workspace.id, status: "active").exists?
    def commercial? = read? && AgentSubscription.find_by(agent_workspace_id: @workspace.id)&.entitled? == true
    alias_method :public?, :commercial?

    def require_commercial!
      raise Pundit::NotAuthorizedError, "Tu plan venció. Podés consultar y exportar tus datos o solicitar la reactivación en Mi plan." unless commercial?
    end
  end
end
