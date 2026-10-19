class CatalogsController < ApplicationController
  before_action -> { require_role!("admin") }

  KINDS = {
    "destination" => Destination,
    "accommodation" => Accommodation,
    "bus" => Bus,
    "boarding_point" => BoardingPoint,
    "route" => Route
  }.freeze

  def show
    load_catalog
  end

  def create
    model = KINDS.fetch(params[:kind])
    record = model.new(catalog_params(params[:kind]))
    record.company = current_company
    if record.save
      redirect_to catalog_path, notice: "Elemento agregado al catálogo."
    else
      load_catalog
      @catalog_error = record.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    model = KINDS.fetch(params[:kind])
    model.where(company: current_company).find(params[:record_id]).destroy!
    redirect_to catalog_path, notice: "Elemento eliminado."
  rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed
    redirect_to catalog_path, alert: "No se puede eliminar porque está en uso."
  end

  private

  def load_catalog
    @destinations = current_company.destinations.order(:name)
    @accommodations = current_company.accommodations.includes(:destination).order(:name)
    @buses = current_company.buses.order(:name)
    @boarding_points = current_company.boarding_points.order(:name)
    @routes = current_company.routes.includes(route_stages: :boarding_point).order(:name)
  end

  def catalog_params(kind)
    case kind
    when "destination"
      params.expect(destination: [ :name, :province, :description ])
    when "accommodation"
      params.expect(accommodation: [ :destination_id, :name, :category, :address, :maps_url, :website_url, :services, :notes ])
    when "bus"
      params.expect(bus: [ :name, :registration, :capacity, :operator_name ])
    when "boarding_point"
      params.expect(boarding_point: [ :name, :address, :latitude, :longitude, :notes ])
    when "route"
      params.expect(route: [ :name, :description ])
    end
  end
end
