class RoomAssignment < ApplicationRecord
  belongs_to :company
  belongs_to :departure
  belongs_to :accommodation
  has_many :room_assignment_passengers, dependent: :destroy
  has_many :passengers, through: :room_assignment_passengers
  validates :room_type, presence: true
end
