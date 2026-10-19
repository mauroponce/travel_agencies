class RouteStage < ApplicationRecord
  belongs_to :route
  belongs_to :boarding_point, optional: true
  belongs_to :accommodation, optional: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :route_id }
  validates :kind, inclusion: { in: %w[boarding hotel return] }
end
