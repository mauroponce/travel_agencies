class ManifestsController < ApplicationController
  def show
    response.headers["Cache-Control"] = "private, no-store"
    departure = current_company.departures.find(params[:departure_id])
    if current_role == "coordinator"
      raise Pundit::NotAuthorizedError unless departure.departure_assignments.exists?(membership: current_membership)
    else
      require_role!("admin")
    end
    passengers = Passenger.with_active_reservations.where(company: current_company).joins(reservation: :departure_offer)
      .where(departure_offers: { departure_id: departure.id }).includes(:departure_stop, :accommodation)
    respond_to do |format|
      format.csv { send_data ManifestExporter.csv(passengers), filename: "manifiesto-#{departure.code}.csv" }
      format.pdf { send_data ManifestExporter.pdf(departure, passengers), filename: "manifiesto-#{departure.code}.pdf", type: "application/pdf", disposition: "attachment" }
    end
  end
end
