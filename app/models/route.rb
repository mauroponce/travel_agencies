class Route < ApplicationRecord
  belongs_to :company
  has_many :route_stages, -> { order(:position) }, dependent: :destroy
  validates :name, presence: true
end
