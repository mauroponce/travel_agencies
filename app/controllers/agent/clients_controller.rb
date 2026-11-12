module Agent
  class ClientsController < BaseController
    before_action :set_client, only: %i[show edit update archive]

    def index
      scope = current_agent_workspace.agent_clients
      scope = scope.active unless params[:archived] == "1"
      @clients, @pagination = paginate(ClientDirectory.call(scope:, query: params[:q]))
    end

    def new = @client = current_agent_workspace.agent_clients.new
    def edit; end

    def show
      @notes, @pagination = paginate(@client.notes.order(created_at: :desc, id: :desc))
      @trips = current_agent_workspace.agent_trips.includes(:current_revision).order(updated_at: :desc)
    end

    def create
      @client = current_agent_workspace.agent_clients.new(client_params)
      if @client.save
        audit("agent_client.created", @client)
        redirect_to agent_client_path(@client), notice: "Cliente registrado."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @client.update(client_params)
        audit("agent_client.updated", @client)
        redirect_to agent_client_path(@client), notice: "Cliente actualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def archive
      @client.update!(archived_at: Time.current)
      audit("agent_client.archived", @client)
      redirect_to agent_clients_path, notice: "Cliente archivado. Conservamos sus notas."
    end

    def export
      notes = params[:notes] == "1"
      send_data ContactExport.call(workspace: current_agent_workspace, notes:), type: "text/csv; charset=utf-8",
        filename: notes ? "notas-privadas.csv" : "contactos-privados.csv", disposition: "attachment"
    end

    private

    def set_client = @client = current_agent_workspace.agent_clients.find(params[:id])
    def client_params = params.expect(agent_client: [ :name, :phone, :email ])
  end
end
