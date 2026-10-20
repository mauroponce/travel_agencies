class SeatAllocation < ApplicationRecord
  belongs_to :company
  belongs_to :departure
  belongs_to :passenger
  validates :passenger_id, uniqueness: true
  validates :status, inclusion: { in: %w[active released] }
  validate :records_share_departure_scope

  private

  def records_share_departure_scope
    return unless passenger && departure
    expected_departure = passenger.reservation.departure_offer.departure_id
    errors.add(:departure, "no coincide con la reserva") if departure_id != expected_departure
    errors.add(:company, "no coincide con el pasajero") if company_id != passenger.company_id
    errors.add(:company, "no coincide con la salida") if company_id != departure.company_id
  end
end
