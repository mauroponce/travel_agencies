class Bus < ApplicationRecord
  belongs_to :company
  has_many :departures, dependent: :restrict_with_error
  validates :name, presence: true
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
end
