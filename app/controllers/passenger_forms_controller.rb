class PassengerFormsController < ApplicationController
  before_action -> { require_role!("reseller") }

  def index
    @forms = PassengerForm.where(company: current_company, reseller_membership: current_membership).order(created_at: :desc)
    @generated_url = public_passenger_form_url(token: flash[:passenger_form_token], host: request.host,
      protocol: request.protocol) if flash[:passenger_form_token].present?
  end

  def create
    offer = current_company.departure_offers.published.find(params[:departure_offer_id])
    form, token = PassengerForm.issue!(company: current_company, departure_offer: offer,
      reseller_membership: current_membership, prefilled_name: params[:prefilled_name])
    redirect_to passenger_forms_path, notice: "Formulario privado creado; no ocupa cupos.",
      flash: { passenger_form_token: token }
  end
end
