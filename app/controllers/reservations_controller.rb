class ReservationsController < ApplicationController
  before_action -> { require_role!("admin", "reseller") }
  before_action :set_reservation, only: %i[show cancel]

  def index
    @reservations = reservation_scope.includes(departure_offer: [ :travel_package, :departure ]).order(created_at: :desc)
  end

  def show; end

  def new
    @offer = available_offers.find(params[:departure_offer_id] || params[:offer_id])
    @reservation = Reservation.new
  end

  def create
    offer = available_offers.find(params[:departure_offer_id])
    channel = current_role == "admin" ? "direct" : "reseller"
    reservation = Reservations::Confirm.call(offer:, actor: current_user, membership: current_membership, channel:,
      passengers: passenger_params, payment: payment_params, idempotency_key: params[:idempotency_key])
    redirect_to reservation, notice: "Reserva #{reservation.code} confirmada."
  rescue Reservations::Confirm::SoldOut, Reservations::Confirm::InsufficientPayment,
    Reservations::Confirm::NotAuthorized, Reservations::Confirm::InvalidPassengers => error
    redirect_to departure_offer_path(offer), alert: error.message
  end

  def cancel
    require_role!("admin")
    Reservations::Cancel.call(reservation: @reservation, actor: current_user, reason: params[:reason])
    redirect_to @reservation, notice: "Reserva cancelada y cupos liberados."
  end

  private

  def reservation_scope
    scope = Reservation.where(company: current_company)
    current_role == "reseller" ? scope.where(seller_membership: current_membership) : scope
  end

  def set_reservation = @reservation = reservation_scope.find(params[:id])
  def available_offers = current_company.departure_offers.published

  def passenger_params
    allowed = %i[ full_name document_number nationality departure_stop_id room_type notes ]
    params.fetch(:passengers, {}).values.map { |passenger| passenger.permit(*allowed).to_h.symbolize_keys }
  end

  def payment_params
    raw = params.expect(payment: [ :amount_cents, :method, :received_on, :notes, :proof ]).to_h.symbolize_keys
    raw[:amount_cents] = raw[:amount_cents].to_s.delete(".").to_i
    raw
  end
end
