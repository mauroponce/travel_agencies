class AgentWorkspacePolicy
  def initialize(context, workspace)
    @context, @workspace = context, workspace
  end

  def access?
    @workspace.active? && @context.user&.id == @workspace.owner_id && @context.agent_workspace&.id == @workspace.id
  end
end
