class BoardingEvent < ApplicationRecord
  belongs_to :company
  belongs_to :departure
  belongs_to :passenger
  belongs_to :recorded_by, class_name: "User"
  validates :command_id, uniqueness: true
  validates :status, inclusion: { in: %w[pending boarded absent incident] }
  validate :passenger_has_confirmed_reservation

  private

  def passenger_has_confirmed_reservation
    return if passenger&.reservation&.status == "confirmed"

    errors.add(:passenger, "debe pertenecer a una reserva confirmada")
  end
end
