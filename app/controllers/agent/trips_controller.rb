module Agent
  class TripsController < BaseController
    before_action :set_trip, only: %i[show edit update publish unpublish archive cover source]
    def index
      @suppliers = current_agent_workspace.agent_suppliers.order(:name, :id)
      @trips, @pagination = paginate(CatalogQuery.call(workspace: current_agent_workspace, filters: params.permit(*CatalogQuery::FILTERS)))
    end
    def new
      @trip = current_agent_workspace.agent_trips.new
      @revision = AgentTripRevision.new(currency: "ARS", price_unit: "per_person")
      @source_import = selected_import
      load_suppliers
    end
    def create
      @trip = SaveTrip.call(workspace: current_agent_workspace, attributes: trip_params, source_import: selected_import, publish: params[:commit_action] == "publish")
      redirect_to agent_trip_path(@trip), notice: "Viaje guardado."
    rescue ActiveRecord::RecordInvalid => error
      @trip ||= current_agent_workspace.agent_trips.new
      @revision = error.record.is_a?(AgentTripRevision) ? error.record : AgentTripRevision.new(trip_params.slice(*AgentTripRevision::FIELDS))
      load_suppliers
      @source_import = selected_import
      @form_error = error.record.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
    def show = @revision = @trip.current_revision
    def edit
      @revision = @trip.current_revision
      load_suppliers
    end
    def update
      SaveTrip.call(workspace: current_agent_workspace, attributes: trip_params, trip: @trip,
        publish: params[:commit_action] == "publish", expected_revision_id: params.require(:expected_revision_id))
      redirect_to agent_trip_path(@trip), notice: "Revisión guardada. La web muestra la última versión que publicaste."
    rescue ActiveRecord::RecordInvalid => error
      @trip.reload
      @revision = AgentTripRevision.new(trip_params.slice(*AgentTripRevision::FIELDS))
      @form_error = error.record.errors.full_messages.to_sentence
      load_suppliers
      render :edit, status: :unprocessable_entity
    end
    def publish
      @trip.publish!
      audit("agent_trip.published", @trip)
      redirect_to agent_trip_path(@trip), notice: "Viaje publicado."
    end
    def unpublish
      @trip.update!(status: "unpublished")
      audit("agent_trip.unpublished", @trip)
      redirect_to agent_trip_path(@trip), notice: "Viaje despublicado."
    end
    def archive
      @trip.update!(status: "archived")
      audit("agent_trip.archived", @trip)
      redirect_to agent_trips_path, notice: "Viaje archivado."
    end
    def cover
      revision = @trip.revisions.find(params[:revision_id].presence || @trip.current_revision_id)
      raise ActiveRecord::RecordNotFound unless revision.cover.attached?
      send_data revision.cover.download, type: revision.cover.content_type, filename: "flyer.#{revision.cover.filename.extension}", disposition: params[:download] ? "attachment" : "inline"
    end
    def source
      revision = @trip.current_revision
      raise ActiveRecord::RecordNotFound unless revision.flyer_source.attached?
      send_data revision.flyer_source.download, filename: revision.flyer_source.filename.to_s, type: revision.flyer_source.content_type, disposition: "attachment"
    end
    def compare
      ids = Array(params[:ids]).uniq
      return render(plain: "Seleccioná dos o tres viajes.", status: :unprocessable_entity) unless ids.size.between?(2, 3)
      @trips = current_agent_workspace.agent_trips.includes(current_revision: :agent_supplier).find(ids)
    end
    private
    def selected_import
      current_agent_workspace.agent_imports.find(params[:source_import_id]) if params[:source_import_id].present?
    end
    def set_trip = @trip = current_agent_workspace.agent_trips.find(params[:id])
    def load_suppliers = @suppliers = current_agent_workspace.agent_suppliers.order(:name, :id)
    def trip_params
      attributes = params.expect(agent_trip_revision: AgentTripRevision::FIELDS + [ "price", "cover", "new_supplier_name" ]).to_h
      attributes["price_cents"] = attributes["price"].present? ? MoneyParser.call(attributes.delete("price")) : nil
      attributes.except("price")
    end
  end
end
