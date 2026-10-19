class RoomAssignmentPassenger < ApplicationRecord
  belongs_to :room_assignment
  belongs_to :passenger
  validates :passenger_id, uniqueness: true
end
