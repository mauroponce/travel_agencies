class FareVersionsController < ApplicationController
  def create
    require_role!("admin")
    offer = current_company.departure_offers.find(params[:departure_offer_id])
    old = offer.current_fare&.price_cents.to_i
    fare = offer.fare_versions.create!(fare_params.merge(valid_from: Time.current, created_by: current_user))
    NotificationDispatcher.fare_changed(offer, old, fare.price_cents)
    AuditRecorder.call(action: "fare.changed", auditable: fare, changeset: { old_price_cents: old, new_price_cents: fare.price_cents })
    redirect_to offer, notice: "Tarifa actualizada."
  end

  private

  def fare_params
    raw = params.expect(fare_version: [ :price_cents, :service_fee_cents, :deposit_type, :deposit_cents, :promotion_label ])
    %i[price_cents service_fee_cents deposit_cents].each { |key| raw[key] = MoneyParser.call(raw[key]) }
    raw
  end
end
