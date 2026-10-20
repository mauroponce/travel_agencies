class RouteStage < ApplicationRecord
  belongs_to :route
  belongs_to :boarding_point, optional: true
  belongs_to :accommodation, optional: true
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :route_id }
  validates :kind, inclusion: { in: %w[boarding hotel return] }
  validate :stage_records_share_route_company

  private

  def stage_records_share_route_company
    return unless route

    errors.add(:boarding_point, "debe pertenecer a la empresa de la ruta") if boarding_point && boarding_point.company_id != route.company_id
    errors.add(:accommodation, "debe pertenecer a la empresa de la ruta") if accommodation && accommodation.company_id != route.company_id
  end
end
