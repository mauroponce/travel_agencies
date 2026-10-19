module Reservations
  class Cancel
    def self.call(reservation:, actor:, reason:)
      ApplicationRecord.transaction do
        reservation.lock!
        return reservation if reservation.status == "cancelled"
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
