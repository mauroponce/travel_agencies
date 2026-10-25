module Agent
  class DashboardController < BaseController
    def show
      workspace = current_agent_workspace
      @metrics = { "Empresas registradas" => workspace.agent_suppliers.count, "Viajes cargados" => workspace.agent_trips.count,
        "Viajes publicados" => workspace.agent_trips.publicly_visible.count, "Borradores" => workspace.agent_trips.where(status: "draft").count }
      @recent = workspace.agent_trips.includes(current_revision: :agent_supplier).order(updated_at: :desc, id: :desc).limit(6)
    end
  end
end
