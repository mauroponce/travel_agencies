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
    destination_scope = current_company.destinations.order(:name)
    @destination_options = destination_scope.to_a
    @destinations, @destinations_pagination = paginate(destination_scope, param: :destinations_page, per_page: 10)
    @accommodations, @accommodations_pagination = paginate(
      current_company.accommodations.includes(:destination).order(:name), param: :accommodations_page, per_page: 10
    )
    @buses, @buses_pagination = paginate(current_company.buses.order(:name), param: :buses_page, per_page: 10)
    @boarding_points, @boarding_points_pagination = paginate(
      current_company.boarding_points.order(:name), param: :boarding_points_page, per_page: 10
    )
    @routes, @routes_pagination = paginate(
      current_company.routes.includes(route_stages: :boarding_point).order(:name), param: :routes_page, per_page: 10
    )
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
