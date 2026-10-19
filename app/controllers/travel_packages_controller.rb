class TravelPackagesController < ApplicationController
  before_action -> { require_role!("admin") }
  before_action :set_package, only: %i[show edit update destroy]

  def index
    @packages = current_company.travel_packages.includes(:destination).order(:name)
  end

  def show; end
  def new = @package = current_company.travel_packages.new
  def edit; end

  def create
    @package = current_company.travel_packages.new(package_params)
    if @package.save
      redirect_to @package, notice: "Paquete creado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @package.update(package_params)
      redirect_to @package, notice: "Paquete actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @package.destroy!
    redirect_to travel_packages_path, notice: "Paquete eliminado."
  end

  private

  def set_package = @package = current_company.travel_packages.find(params[:id])

  def package_params
    raw = params.expect(travel_package: [ :destination_id, :name, :description, :days, :nights,
      :commercial_terms, :included_services, :excluded_services, { images: [] } ])
    %i[included_services excluded_services].each do |key|
      raw[key] = raw[key].to_s.lines.map(&:strip).compact_blank
    end
    raw
  end
end
