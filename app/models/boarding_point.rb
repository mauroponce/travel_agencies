class BoardingPoint < ApplicationRecord
  belongs_to :company
  validates :name, :address, presence: true
end
