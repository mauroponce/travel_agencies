module Agent
  class ImportItemsController < BaseController
    before_action :set_item
    def edit
      prepare_review
    end
    def update
      raw = params.expect(agent_trip_revision: AgentTripRevision::FIELDS + [ "price", "cover" ]).to_h
      # Persist corrections before supplier creation or publication validation.
      @item.update!(review_data: @item.review_data.merge(raw.except("cover")))
      if params[:commit_action] == "create_supplier"
        supplier = current_agent_workspace.agent_suppliers.create!(name: params.require(:new_supplier_name))
        @item.update!(review_data: @item.review_data.merge("agent_supplier_id" => supplier.id))
        return redirect_to edit_agent_import_item_path(@import, @item), notice: "Empresa creada. Tus correcciones se conservaron."
      end
      return redirect_to(edit_agent_import_item_path(@import, @item), notice: "Revisión guardada.") if params[:commit_action] == "review"
      raw["price_cents"] = raw["price"].present? ? MoneyParser.call(raw.delete("price")) : nil
      raw.delete("price")
      target = current_agent_workspace.agent_trips.find(params[:target_trip_id]) if params[:target_trip_id].present?
      trip = SaveTrip.call(workspace: current_agent_workspace, attributes: raw, item: @item, trip: target,
        expected_revision_id: target ? params[:expected_revision_id].to_s : nil, publish: params[:commit_action] == "publish")
      redirect_to agent_trip_path(trip), notice: "Ficha guardada."
    rescue ActiveRecord::RecordInvalid, MoneyParser::InvalidAmount, UploadValidator::Invalid, ActiveRecord::RecordNotUnique, ActiveRecord::StaleObjectError => error
      @review_error = form_error_message(error)
      prepare_review
      render :edit, status: error.is_a?(ActiveRecord::StaleObjectError) ? :conflict : :unprocessable_entity
    end
    private
    def set_item
      @import = current_agent_workspace.agent_imports.find(params[:import_id])
      @item = @import.items.find(params[:id])
    end
    def prepare_review
      data = @item.extracted.slice(*AgentTripRevision::FIELDS).merge(@item.review_data.except("price"))
      if @item.review_data.key?("price")
        data["price_cents"] = begin
          @item.review_data["price"].present? ? MoneyParser.call(@item.review_data["price"]) : nil
        rescue MoneyParser::InvalidAmount
          nil
        end
      end
      @revision = AgentTripRevision.new(data)
      @suppliers = current_agent_workspace.agent_suppliers.order(:name, :id)
      @candidates = current_agent_workspace.agent_trips.joins(:current_revision).includes(current_revision: :agent_supplier)
      if @revision.destination.present?
        @candidates = @candidates.where("unaccent(lower(agent_trip_revisions.destination)) = unaccent(?)", @revision.destination.downcase)
      else
        @candidates = @candidates.none
      end
      @candidates = @candidates.where(agent_trip_revisions: { departs_on: @revision.departs_on }) if @revision.departs_on
      @candidates = @candidates.where(agent_trip_revisions: { agent_supplier_id: @revision.agent_supplier_id }) if @revision.agent_supplier_id
      @candidates = @candidates.order(updated_at: :desc, id: :desc).limit(10)
    end
  end
end
