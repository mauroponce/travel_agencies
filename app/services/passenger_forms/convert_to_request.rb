module PassengerForms
  class ConvertToRequest
    def self.call(form:, actor:, membership:)
      new(form:, actor:, membership:).call
    end

    def initialize(form:, actor:, membership:)
      @form = form
      @actor = actor
      @membership = membership
    end

    def call
      raise Pundit::NotAuthorizedError unless @form.reseller_membership_id == @membership.id &&
        @form.company_id == @membership.company_id

      ApplicationRecord.transaction do
        @form.lock!
        next @form.reservation if @form.reservation

        submission = @form.passenger_form_submission || raise(ActiveRecord::RecordNotFound, "El formulario no fue recibido")
        offer = @form.departure_offer
        offer.lock!
        fare = offer.current_fare
        reservation = Reservation.create!(company: @form.company, departure_offer: offer,
          seller_membership: @membership, created_by: @actor, code: next_code,
          channel: "reseller", status: "requested", unit_price_cents: fare&.price_cents,
          unit_fee_cents: fare&.service_fee_cents, minimum_payment_cents: fare&.required_payment_cents,
          terms_snapshot: fare ? { deposit_type: fare.deposit_type, promotion_label: fare.promotion_label } : {})
        reservation.passengers.create!(company: @form.company, departure_stop: submission.departure_stop,
          accommodation: offer.accommodation, full_name: submission.full_name,
          document_number: submission.document_number, document_last4: submission.document_last4,
          nationality: submission.nationality, room_type: submission.room_type, notes: submission.notes)
        @form.update!(reservation:)
        reservation
      end
    rescue ActiveRecord::RecordNotUnique
      @form.reload.reservation || raise
    end

    private

    def next_code
      "NV-SOL-#{Time.current.strftime('%y%m')}-#{SecureRandom.hex(3).upcase}"
    end
  end
end
