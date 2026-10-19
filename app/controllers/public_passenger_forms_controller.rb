class PublicPassengerFormsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context
  before_action :set_form

  def show
    return render :unavailable, status: :gone unless @form&.available?
    @offer = @form.departure_offer
  end

  def create
    return render :unavailable, status: :gone unless @form&.available?
    attributes = submission_params
    document = attributes.delete(:document_number).to_s.strip
    ApplicationRecord.transaction do
      @form.create_passenger_form_submission!(attributes.merge(document_number: document, document_last4: document.last(4)))
      @form.update!(submitted_at: Time.current)
    end
    NotificationDispatcher.dispatch([ @form.reseller_membership.user ], company: @form.company,
      event_type: "passenger_form_submitted", title: "Datos de pasajero recibidos",
      body: "Se completó un formulario para #{@form.departure_offer.travel_package.name}.",
      action_url: passenger_forms_path)
    render :completed
  rescue ActiveRecord::RecordInvalid
    @offer = @form.departure_offer
    render :show, status: :unprocessable_entity
  end

  private

  def set_form = @form = PassengerForm.find_by_token(params[:token])

  def submission_params
    params.expect(passenger_form_submission: [ :full_name, :document_number, :nationality, :departure_stop_id, :room_type, :notes ]).to_h.symbolize_keys
  end
end
