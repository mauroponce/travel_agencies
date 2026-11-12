module Agent
  class PlansController < BaseController
    def show
      @subscription = current_agent_workspace.agent_subscription
    end

    def request_activation
      Subscriptions.request_activation!(workspace: current_agent_workspace)
      redirect_to agent_plan_path, notice: "Solicitud registrada. La plataforma coordinará la activación manual; no hay débito automático."
    end

    def cancel
      Subscriptions.cancel!(workspace: current_agent_workspace)
      redirect_to agent_plan_path, notice: "Conservás el acceso hasta el vencimiento. No hay débito automático."
    end
  end
end
