class DepartureOffersController < ApplicationController
  before_action -> { require_role!("admin", "reseller") }
  before_action :set_offer, only: %i[show edit update publish unpublish]

  def index
    @offers = current_company.departure_offers.includes(:travel_package, :departure, :accommodation).order(created_at: :desc)
  end

  def show; end
  def new
    require_role!("admin")
    @offer = current_company.departure_offers.new
  end
  def edit = require_role!("admin")

  def create
    require_role!("admin")
    @offer = current_company.departure_offers.new(offer_params)
    if @offer.save
      create_initial_fare(@offer)
      redirect_to @offer, notice: "Oferta creada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    require_role!("admin")
    updated = ApplicationRecord.transaction do
      @offer.lock!
      @offer.update(offer_params)
    end
    if updated
      redirect_to @offer, notice: "Oferta actualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def publish
    require_role!("admin")
    raise ActiveRecord::RecordInvalid, @offer unless @offer.current_fare
    @offer.update!(status: "published", published_at: Time.current)
    NotificationDispatcher.offer_published(@offer)
    redirect_to @offer, notice: "Oferta publicada y revendedores notificados."
  end

  def unpublish
    require_role!("admin")
    @offer.update!(status: "unpublished")
    redirect_to @offer, notice: "Oferta despublicada."
  end

  private

  def set_offer
    scope = current_company.departure_offers.includes(:travel_package, :departure, :accommodation, :fare_versions)
    @offer = scope.find(params[:id])
  end

  def offer_params
    params.expect(departure_offer: [ :travel_package_id, :departure_id, :accommodation_id, :slug ])
  end

  def create_initial_fare(offer)
    return unless params[:fare]
    offer.fare_versions.create!(fare_params.merge(valid_from: Time.current, created_by: current_user))
  end

  def fare_params
    raw = params.expect(fare: [ :price_cents, :service_fee_cents, :deposit_type, :deposit_cents, :promotion_label ])
    %i[price_cents service_fee_cents deposit_cents].each { |key| raw[key] = MoneyParser.call(raw[key]) }
    raw
  end
end
