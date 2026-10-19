class DepartureStop < ApplicationRecord
  belongs_to :departure
  belongs_to :boarding_point
  has_many :passengers, dependent: :restrict_with_error
  validates :position, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :departure_id }
  validates :published_name, :published_address, :scheduled_at, presence: true
  validate :boarding_point_shares_company

  private

  def boarding_point_shares_company
    return unless departure && boarding_point
    errors.add(:boarding_point, "debe pertenecer a la empresa") if departure.company_id != boarding_point.company_id
  end
end
