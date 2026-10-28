module Agent
  class PublicCatalogController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :set_current_context
    before_action :prepare_public_context
    layout "agent"
    def index
      return unless current_agent_workspace.show_catalog?
      @owner_view = current_user.present? && current_user.id == current_agent_workspace.owner_id
      @suppliers = if @owner_view
        current_agent_workspace.agent_suppliers.order(:name, :id)
      else
        current_agent_workspace.agent_suppliers.active.where(id: current_agent_workspace.agent_trips.publicly_visible.joins(:published_revision).select("agent_trip_revisions.agent_supplier_id")).order(:name, :id)
      end
      @trips, @pagination = paginate(CatalogQuery.call(workspace: current_agent_workspace, filters: params.permit(*CatalogQuery::FILTERS), public_view: !@owner_view))
    end
    def search
      raise ActiveRecord::RecordNotFound unless current_agent_workspace.show_catalog?
      query = params[:q].to_s.strip.first(200)
      trips = query.length < 2 ? [] : CatalogQuery.call(workspace: current_agent_workspace, filters: { q: query }, public_view: true).limit(6)
      render json: { results: trips.map do |trip|
        revision = trip.published_revision
        { title: revision.title, destination: revision.destination, date: revision.departs_on.strftime("%d/%m/%Y"),
          price: helpers.agent_money(revision), url: helpers.agent_trip_public_url(trip),
          image_url: (helpers.agent_image_public_url(trip, revision) if revision.cover.attached?) }
      end }
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
    def about_photo
      photo = current_agent_workspace.about_photo
      raise ActiveRecord::RecordNotFound unless current_agent_workspace.show_about? && photo.attached? && photo.blob_id == params[:blob_id]
      send_data photo.download, type: photo.content_type, disposition: "inline"
    end
    private
    def prepare_public_context
      raise ActiveRecord::RecordNotFound unless AgentWorkspace.enabled? && current_agent_workspace&.active?
      @public_view = true
      Time.zone = current_agent_workspace.timezone
      response.headers["Cache-Control"] = "no-store"
    end
  end
end
