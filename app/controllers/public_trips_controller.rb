class PublicTripsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context
  before_action :set_offer

  def show
    @fare = @offer.current_fare
    @reseller = reseller_from_reference
    @contact_phone = @reseller&.user&.phone.presence || @offer.company.whatsapp
    return not_found unless @fare
    response.headers["Cache-Control"] = "public, max-age=30, stale-while-revalidate=60"
  end

  def status
    fare = @offer.current_fare
    return head :not_found unless fare
    payload = { price_cents: fare.price_cents, service_fee_cents: fare.service_fee_cents,
               promotion_label: fare.promotion_label, available_seats: @offer.available_seats,
               sold_out: @offer.available_seats.zero? || @offer.departure.status != "open",
               updated_at: [ fare.updated_at, @offer.departure.updated_at ].max.iso8601 }
    fresh_when(etag: payload, public: true)
    render json: payload unless performed?
  end

  private

  def set_offer
    company = Company.find_by!(slug: params[:company_slug], status: "active")
    @offer = company.departure_offers.published.includes(:travel_package, :departure, :accommodation, :fare_versions).find_by!(slug: params[:offer_slug])
  end

  def reseller_from_reference
    return if params[:ref].blank?
    authorization = ResellerAuthorization.find_by(public_code: params[:ref], status: "active")
    authorization&.membership if authorization&.membership&.company_id == @offer.company_id
  end
end
