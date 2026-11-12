module Agent
  class ClientNotesController < BaseController
    def create
      client = current_agent_workspace.agent_clients.find(params[:client_id])
      attributes = params.expect(agent_client_note: [ :body, :agent_trip_id ]).to_h
      trip = current_agent_workspace.agent_trips.find(attributes["agent_trip_id"]) if attributes["agent_trip_id"].present?
      note = client.notes.create!(agent_workspace: current_agent_workspace, body: attributes["body"], agent_trip: trip)
      audit("agent_client_note.created", note)
      redirect_to agent_client_path(client), notice: "Nota privada guardada."
    end
  end
end
