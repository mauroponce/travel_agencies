class BoardingEvent < ApplicationRecord
  belongs_to :company
  belongs_to :departure
  belongs_to :passenger
  belongs_to :recorded_by, class_name: "User"
  validates :command_id, uniqueness: true
  validates :status, inclusion: { in: %w[pending boarded absent incident] }
end
