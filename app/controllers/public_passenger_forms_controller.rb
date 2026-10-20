class PublicPassengerFormsController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context
  before_action :set_form

  def show
    return render :unavailable, status: :gone unless form_available?
    @offer = @form.departure_offer
  end

  def create
    return render :unavailable, status: :gone unless @form&.company&.status == "active"
    attributes = submission_params
    document = attributes.delete(:document_number).to_s.strip
    created = false
    company_active = false
    ApplicationRecord.transaction do
      @form.lock!
      company_active = @form.company.reload.status == "active"
      next unless company_active && @form.available?

      @form.create_passenger_form_submission!(attributes.merge(document_number: document, document_last4: document.last(4)))
      @form.update!(submitted_at: Time.current)
      created = true
    end
    return render :unavailable, status: :gone unless company_active

    if created
      NotificationDispatcher.dispatch([ @form.reseller_membership.user ], company: @form.company,
        event_type: "passenger_form_submitted", title: "Datos de pasajero recibidos",
        body: "Se completó un formulario para #{@form.departure_offer.travel_package.name}.",
        action_url: passenger_forms_path)
    end
    render :completed
  rescue ActiveRecord::RecordInvalid
    @offer = @form.departure_offer
    render :show, status: :unprocessable_entity
  end

  private

  def set_form
    form = PassengerForm.find_by_token(params[:token])
    @form = form if form&.company_id == current_company&.id
  end

  def form_available?
    @form&.company&.status == "active" && @form.available?
  end

  def submission_params
    params.expect(passenger_form_submission: [ :full_name, :document_number, :nationality, :departure_stop_id, :room_type, :notes ]).to_h.symbolize_keys
  end
end
