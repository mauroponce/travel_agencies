class DeparturesController < ApplicationController
  before_action :set_departure, only: %i[show edit update destroy operation]

  def index
    @departures = departure_scope.includes(:bus, :departure_offers).order(:departs_at)
  end

  def show; end
  def new
    require_role!("admin")
    @departure = current_company.departures.new
  end
  def edit = require_role!("admin")

  def create
    require_role!("admin")
    @departure = current_company.departures.new(departure_params)
    if @departure.save
      copy_route_stops(@departure)
      redirect_to @departure, notice: "Salida creada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    require_role!("admin")
    if @departure.update(departure_params)
      redirect_to @departure, notice: "Salida actualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    require_role!("admin")
    @departure.destroy!
    redirect_to departures_path, notice: "Salida eliminada."
  end

  def operation
    if current_role == "coordinator"
      raise Pundit::NotAuthorizedError unless @departure.departure_assignments.exists?(membership: current_membership)
    else
      require_role!("admin")
    end
    @stops = @departure.departure_stops.includes(passengers: [ :accommodation, :boarding_events ])
  end

  private

  def set_departure = @departure = departure_scope.find(params[:id])

  def departure_scope
    scope = current_company.departures
    current_role == "coordinator" ? scope.joins(:departure_assignments).where(departure_assignments: { membership_id: current_membership.id }) : scope
  end

  def departure_params
    params.expect(departure: [ :bus_id, :route_id, :code, :departs_at, :returns_at, :capacity, :status, :return_notes ])
  end

  def copy_route_stops(departure)
    return unless departure.route
    departure.route.route_stages.where(kind: "boarding").includes(:boarding_point).each do |stage|
      point = stage.boarding_point
      departure.departure_stops.create!(boarding_point: point, position: stage.position,
        scheduled_at: departure.departs_at, published_name: point.name, published_address: point.address,
        instructions: stage.instructions)
    end
  end
end
