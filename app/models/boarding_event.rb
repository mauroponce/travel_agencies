class BoardingEvent < ApplicationRecord
  belongs_to :company
  belongs_to :departure
  belongs_to :passenger
  belongs_to :recorded_by, class_name: "User"
  validates :command_id, uniqueness: true
  validates :status, inclusion: { in: %w[pending boarded absent incident] }
  validate :records_share_operation_scope

  private

  def records_share_operation_scope
    return unless passenger && departure

    reservation = passenger.reservation
    allocation = passenger.seat_allocation
    errors.add(:passenger, "debe pertenecer a la empresa") if passenger.company_id != company_id
    errors.add(:departure, "debe pertenecer a la empresa") if departure.company_id != company_id
    errors.add(:passenger, "debe pertenecer a una reserva confirmada") unless reservation.status == "confirmed"
    errors.add(:passenger, "debe tener un cupo activo en la salida") unless allocation&.status == "active" && allocation.departure_id == departure_id
  end
end
