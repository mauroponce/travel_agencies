module Agent
  class ExportsController < BaseController
    def show
      workspace = current_agent_workspace
      data = {
        workspace: workspace.attributes.slice("business_name", "public_name", "slug", "whatsapp", "presentation", "about_text", "timezone"),
        suppliers: workspace.agent_suppliers.map(&:attributes),
        trips: workspace.agent_trips.map(&:attributes),
        revisions: workspace.agent_trip_revisions.map(&:attributes),
        imports: workspace.agent_imports.map { |item| item.attributes.merge("items" => item.items.map(&:attributes)) },
        clients: workspace.agent_clients.map { |client| client.attributes.merge("notes" => client.notes.map(&:attributes)) }
      }
      send_data JSON.pretty_generate(data), type: "application/json", filename: "turistack-pro.json", disposition: "attachment"
    end
  end
end
