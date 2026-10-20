class RoomAssignmentPassenger < ApplicationRecord
  belongs_to :room_assignment
  belongs_to :passenger
  validates :passenger_id, uniqueness: true
  validate :passenger_matches_assignment

  private

  def passenger_matches_assignment
    return unless room_assignment && passenger

    errors.add(:passenger, "debe pertenecer a la empresa") if passenger.company_id != room_assignment.company_id
    expected_departure_id = passenger.reservation.departure_offer.departure_id
    errors.add(:passenger, "debe viajar en la salida de la habitación") if expected_departure_id != room_assignment.departure_id
    errors.add(:passenger, "debe alojarse en el hotel de la habitación") if passenger.accommodation_id != room_assignment.accommodation_id
  end
end
