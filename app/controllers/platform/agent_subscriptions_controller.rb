module Platform
  class AgentSubscriptionsController < ApplicationController
    def create
      Agent::Subscriptions.grant_month!(workspace: AgentWorkspace.find(params[:agent_workspace_id]), actor: current_user)
      redirect_to platform_agent_workspaces_path, notice: "Se agregó un mes de Pro manualmente."
    end
  end
end
