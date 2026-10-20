module Reservations
  class Cancel
    class NotAuthorized < StandardError; end
    class InvalidTransition < StandardError; end

    def self.call(reservation:, actor:, membership:, reason:)
      unless membership&.company_id == reservation.company_id && membership.role?("admin")
        raise NotAuthorized, "El perfil no puede cancelar esta reserva"
      end

      ApplicationRecord.transaction do
        raise NotAuthorized, "La empresa está suspendida" unless reservation.company.reload.status == "active"

        reservation.lock!
        return reservation if reservation.status == "cancelled"
        raise InvalidTransition, "Solo se pueden cancelar reservas confirmadas" unless reservation.status == "confirmed"

        reservation.departure_offer.departure.lock!
        reservation.passengers.includes(:seat_allocation).each do |passenger|
          passenger.seat_allocation&.update!(status: "released", released_at: Time.current)
        end
        reservation.update!(status: "cancelled", cancelled_at: Time.current, cancellation_reason: reason)
        AuditRecorder.call(action: "reservation.cancelled", auditable: reservation, actor:, company: reservation.company,
          changeset: { reason: })
        reservation
      end
    end
  end
end
