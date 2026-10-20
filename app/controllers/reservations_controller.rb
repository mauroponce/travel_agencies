class ReservationsController < ApplicationController
  before_action -> { require_role!("admin", "reseller") }
  before_action :set_reservation, only: %i[show cancel confirm]

  def index
    @reservations, @reservations_pagination = paginate(
      reservation_scope.includes(:passengers, departure_offer: [ :travel_package, :departure ]).order(created_at: :desc),
      per_page: 25
    )
  end

  def show; end

  def new
    @passenger_form = submitted_form_scope.find(params[:passenger_form_id]) if params[:passenger_form_id].present?
    return redirect_to(@passenger_form.reservation) if @passenger_form&.reservation

    @offer = @passenger_form&.departure_offer || available_offers.find(params[:departure_offer_id] || params[:offer_id])
    @passenger_seed = @passenger_form&.passenger_form_submission
    @reservation = Reservation.new
  end

  def create
    offer = available_offers.find(params[:departure_offer_id])
    passenger_form = submitted_form_scope.find(params[:passenger_form_id]) if params[:passenger_form_id].present?
    channel = current_role == "admin" ? "direct" : "reseller"
    reservation = Reservations::Confirm.call(offer:, actor: current_user, membership: current_membership, channel:,
      passengers: passenger_params, payment: payment_params, idempotency_key: params[:idempotency_key], passenger_form:)
    redirect_to reservation, notice: "Reserva #{reservation.code} confirmada."
  rescue Reservations::Confirm::SoldOut, Reservations::Confirm::InsufficientPayment,
    Reservations::Confirm::NotAuthorized, Reservations::Confirm::InvalidPassengers,
    Reservations::Confirm::NotAvailable, MoneyParser::InvalidAmount => error
    redirect_to departure_offer_path(offer), alert: error.message
  end

  def cancel
    require_role!("admin")
    Reservations::Cancel.call(reservation: @reservation, actor: current_user, membership: current_membership,
      reason: params[:reason])
    redirect_to @reservation, notice: "Reserva cancelada y cupos liberados."
  rescue Reservations::Cancel::NotAuthorized, Reservations::Cancel::InvalidTransition => error
    redirect_to @reservation, alert: error.message
  end

  def confirm
    require_role!("reseller")
    reservation = Reservations::Confirm.call(reservation: @reservation, actor: current_user,
      membership: current_membership, payment: payment_params)
    redirect_to reservation, notice: "Reserva #{reservation.code} confirmada; los cupos ya fueron asignados."
  rescue Reservations::Confirm::SoldOut, Reservations::Confirm::InsufficientPayment,
    Reservations::Confirm::NotAuthorized, Reservations::Confirm::InvalidPassengers,
    Reservations::Confirm::NotAvailable, MoneyParser::InvalidAmount => error
    redirect_to @reservation, alert: error.message
  end

  private

  def reservation_scope
    scope = Reservation.where(company: current_company)
    current_role == "reseller" ? scope.where(seller_membership: current_membership) : scope
  end

  def set_reservation = @reservation = reservation_scope.find(params[:id])
  def available_offers = current_company.departure_offers.published

  def submitted_form_scope
    PassengerForm.where(company: current_company, reseller_membership: current_membership).where.not(submitted_at: nil)
  end

  def passenger_params
    allowed = %i[ full_name document_number nationality departure_stop_id room_type notes ]
    params.fetch(:passengers, {}).values.map { |passenger| passenger.permit(*allowed).to_h.symbolize_keys }
  end

  def payment_params
    raw = params.expect(payment: [ :amount_cents, :method, :received_on, :notes, :proof ]).to_h.symbolize_keys
    raw[:amount_cents] = MoneyParser.call(raw[:amount_cents])
    raw
  end
end
