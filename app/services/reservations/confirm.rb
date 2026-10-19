module Reservations
  class Confirm
    class SoldOut < StandardError; end
    class NotAuthorized < StandardError; end
    class InsufficientPayment < StandardError; end
    class InvalidPassengers < StandardError; end
    class NotAvailable < StandardError; end

    def self.call(**arguments) = new(**arguments).call

    def initialize(offer:, actor:, membership:, channel:, passengers:, payment:, idempotency_key:, passenger_form: nil)
      @offer = offer
      @actor = actor
      @membership = membership
      @channel = channel
      @passenger_attributes = passengers
      @payment_attributes = payment
      @idempotency_key = idempotency_key.presence || SecureRandom.uuid
      @passenger_form = passenger_form
    end

    def call
      raise InvalidPassengers, "Agregá al menos un pasajero" if @passenger_attributes.empty?

      existing = Reservation.find_by(company: @offer.company, idempotency_key: @idempotency_key)
      return existing if existing

      created = false
      reservation = ApplicationRecord.transaction do
        @passenger_form&.lock!
        next @passenger_form.reservation if @passenger_form&.reservation

        @offer.lock!
        departure = @offer.departure.lock!
        validate_sale_available!(departure)
        validate_passenger_form!
        authorize_channel!
        fare = @offer.current_fare || raise(ActiveRecord::RecordNotFound, "No hay tarifa vigente")
        raise SoldOut, "No quedan cupos suficientes" if departure.available_seats < @passenger_attributes.size

        required = fare.required_payment_cents * @passenger_attributes.size
        received = Integer(@payment_attributes.fetch(:amount_cents))
        raise InsufficientPayment, "El pago declarado no alcanza el mínimo de reserva" if received < required

        reservation = Reservation.create!(company: @offer.company, departure_offer: @offer,
          seller_membership: (@membership if @channel == "reseller"), created_by: @actor,
          code: next_code, channel: @channel, status: "confirmed", idempotency_key: @idempotency_key,
          unit_price_cents: fare.price_cents, unit_fee_cents: fare.service_fee_cents,
          minimum_payment_cents: fare.required_payment_cents,
          terms_snapshot: { deposit_type: fare.deposit_type, promotion_label: fare.promotion_label },
          confirmed_at: Time.current)

        @passenger_attributes.each do |attributes|
          document = attributes.fetch(:document_number).to_s.strip
          passenger = reservation.passengers.create!(company: @offer.company,
            departure_stop_id: attributes.fetch(:departure_stop_id), accommodation: @offer.accommodation,
            full_name: attributes.fetch(:full_name), document_number: document,
            document_last4: document.last(4), nationality: attributes.fetch(:nationality, "Argentina"),
            room_type: attributes[:room_type], notes: attributes[:notes])
          SeatAllocation.create!(company: @offer.company, departure:, passenger:)
        end

        payment = reservation.customer_payments.create!(company: @offer.company, recorded_by: @actor,
          received_by_membership: (@membership if @channel == "reseller"), amount_cents: received,
          method: @payment_attributes.fetch(:method), received_on: @payment_attributes.fetch(:received_on, Date.current),
          notes: @payment_attributes[:notes])
        payment.proof.attach(@payment_attributes[:proof]) if @payment_attributes[:proof].present?
        create_commission!(reservation)
        @passenger_form&.update!(reservation:)
        AuditRecorder.call(action: "reservation.confirmed", auditable: reservation,
          actor: @actor, company: @offer.company, changeset: { passengers: @passenger_attributes.size, amount_cents: received })
        created = true
        reservation
      end

      NotificationDispatcher.reservation_confirmed(reservation) if created
      reservation
    rescue ActiveRecord::RecordNotUnique
      @passenger_form&.reload&.reservation ||
        Reservation.find_by!(company: @offer.company, idempotency_key: @idempotency_key)
    end

    private

    def authorize_channel!
      return if @channel == "direct" && @membership&.role?("admin") && @membership.company_id == @offer.company_id
      authorization = @membership&.reseller_authorization
      valid = @channel == "reseller" && @membership&.company_id == @offer.company_id &&
        authorization&.active? && authorization.auto_confirm_enabled?
      raise NotAuthorized, "El perfil no puede confirmar esta reserva" unless valid
    end

    def validate_sale_available!(departure)
      return if @offer.status == "published" && departure.status == "open"

      raise NotAvailable, "La salida debe estar abierta y la oferta publicada para confirmar reservas"
    end

    def validate_passenger_form!
      return unless @passenger_form

      valid = @passenger_form.company_id == @offer.company_id &&
        @passenger_form.departure_offer_id == @offer.id &&
        @passenger_form.reseller_membership_id == @membership&.id &&
        @passenger_form.passenger_form_submission.present?
      raise NotAuthorized, "El formulario no puede convertirse en esta reserva" unless valid
    end

    def create_commission!(reservation)
      return if @channel == "direct"
      rule = CommissionRule.where(company: @offer.company, reseller_membership: @membership, status: "active").order(created_at: :desc).first
      return unless rule
      total = reservation.passengers.size * (reservation.unit_price_cents + reservation.unit_fee_cents)
      CommissionEntry.create!(company: @offer.company, reservation:, reseller_membership: @membership,
        amount_cents: rule.calculate(total), calculation_kind: rule.kind,
        rule_snapshot: { kind: rule.kind, percentage: rule.percentage, fixed_cents: rule.fixed_cents })
    end

    def next_code
      "NV-#{Time.current.strftime('%y%m')}-#{SecureRandom.hex(3).upcase}"
    end
  end
end
