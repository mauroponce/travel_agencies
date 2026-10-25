module Agent
  class PublicCatalogController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :set_current_context
    before_action :prepare_public_context
    layout "agent"
    def index
      @suppliers = current_agent_workspace.agent_suppliers.active.where(id: current_agent_workspace.agent_trips.publicly_visible.joins(:published_revision).select("agent_trip_revisions.agent_supplier_id")).order(:name, :id)
      @trips, @pagination = paginate(CatalogQuery.call(workspace: current_agent_workspace, filters: params.permit(*CatalogQuery::FILTERS), public_view: true))
    end
    def show
      @trip = current_agent_workspace.agent_trips.publicly_visible.find_by!(slug: params[:slug])
      @revision = @trip.published_revision
    end
    def image
      trip = current_agent_workspace.agent_trips.publicly_visible.find_by!(slug: params[:slug])
      revision = trip.published_revision
      raise ActiveRecord::RecordNotFound unless revision.id == params[:revision_id] && revision.cover.attached?
      response.headers["Cache-Control"] = "no-store"
      send_data revision.cover.download, type: revision.cover.content_type, filename: "flyer.#{revision.cover.filename.extension}", disposition: "inline"
    end
    private
    def prepare_public_context
      @public_view = true
      Time.zone = current_agent_workspace.timezone
      response.headers["Cache-Control"] = "no-store"
    end
  end
end
