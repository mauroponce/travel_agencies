class DashboardController < ApplicationController
  def show
    return redirect_to(departures_path) if current_role == "coordinator"

    departure_scope = current_company.departures.where("departs_at >= ?", Time.current.beginning_of_day)
      .where(status: %w[open sold_out])
    offer_scope = current_company.departure_offers
    reservation_scope = Reservation.where(company: current_company)
    payment_scope = CustomerPayment.where(company: current_company)
    remittance_scope = Remittance.where(company: current_company)

    if current_role == "reseller"
      departure_scope = departure_scope.joins(:departure_offers)
        .where(departure_offers: { status: "published" }).distinct
      offer_scope = offer_scope.published
      reservation_scope = reservation_scope.where(seller_membership: current_membership)
      payment_scope = payment_scope.where(received_by_membership: current_membership)
      remittance_scope = remittance_scope.where(reseller_membership: current_membership)
    end

    @departures = departure_scope.includes(:bus, :seat_allocations).order(:departs_at).limit(5)
    @offers = offer_scope.includes(:travel_package, :departure, :accommodation, :fare_versions)
      .order(created_at: :desc).limit(6)
    @reservations = reservation_scope.includes(:passengers, departure_offer: :travel_package)
      .order(created_at: :desc).limit(6)

    metric_departures = departure_scope.includes(:seat_allocations).to_a
    pending_remittances = remittance_scope.where(status: "declared")
    pending_payments = payment_scope.where.not(received_by_membership_id: nil)
      .where(status: %w[declared partially_remitted])
      .includes(remittance_allocations: :remittance).to_a
    @metrics = {
      upcoming_departures: metric_departures.size,
      confirmed_passengers: Passenger.where(reservation_id: reservation_scope.where(status: "confirmed").select(:id)).count,
      available_seats: metric_departures.sum(&:available_seats),
      pending_reservations: reservation_scope.where(status: "requested").count,
      registered_payments_cents: payment_scope.where.not(status: "voided").sum(:amount_cents),
      pending_remittances: pending_remittances.count,
      pending_verification_cents: pending_remittances.sum(:amount_cents),
      pending_remittance_cents: pending_payments.sum(&:pending_remittance_cents)
    }
  end
end
