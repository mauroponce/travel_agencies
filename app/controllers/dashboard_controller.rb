class DashboardController < ApplicationController
  def show
    return redirect_to(departures_path) if current_role == "coordinator"

    @departures = current_company.departures.where.not(status: "cancelled").order(:departs_at).limit(5)
    @offers = current_company.departure_offers.includes(:travel_package, :departure, :accommodation).order(created_at: :desc).limit(6)
    scope = Reservation.where(company: current_company)
    scope = scope.where(seller_membership: current_membership) if current_role == "reseller"
    @reservations = scope.order(created_at: :desc).limit(6)
    @pending_remittances = Remittance.where(company: current_company, status: "declared")
  end
end
