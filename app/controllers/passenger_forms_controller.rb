class PassengerFormsController < ApplicationController
  before_action -> { require_role!("reseller") }
  before_action :set_form, only: %i[show convert]

  def index
    @forms = form_scope.includes(:passenger_form_submission, :reservation).order(created_at: :desc)
    @generated_url = CompanyUrl.call(current_company,
      path: public_passenger_form_path(flash[:passenger_form_token])) if flash[:passenger_form_token].present?
  end

  def create
    offer = current_company.departure_offers.published.find(params[:departure_offer_id])
    form, token = PassengerForm.issue!(company: current_company, departure_offer: offer,
      reseller_membership: current_membership, prefilled_name: params[:prefilled_name])
    redirect_to passenger_forms_path, notice: "Formulario privado creado; no ocupa cupos.",
      flash: { passenger_form_token: token }
  end

  def show; end

  def convert
    reservation = PassengerForms::ConvertToRequest.call(form: @form, actor: current_user, membership: current_membership)
    redirect_to reservation, notice: "Solicitud creada sin ocupar cupos."
  end

  private

  def form_scope
    PassengerForm.where(company: current_company, reseller_membership: current_membership)
  end

  def set_form
    @form = form_scope.includes(:passenger_form_submission, :reservation, departure_offer: :travel_package).find(params[:id])
  end
end
