class Departure < ApplicationRecord
  belongs_to :company
  belongs_to :bus
  belongs_to :route, optional: true
  has_many :departure_stops, -> { order(:position) }, dependent: :destroy
  has_many :departure_offers, dependent: :restrict_with_error
  has_many :seat_allocations, dependent: :restrict_with_error
  has_many :departure_assignments, dependent: :destroy

  validates :code, presence: true, uniqueness: { scope: :company_id }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[draft open sold_out cancelled completed] }
  validate :catalog_records_share_company

  def occupied_seats
    seat_allocations.where(status: "active").count
  end

  def available_seats
    [ capacity - occupied_seats, 0 ].max
  end

  private

  def catalog_records_share_company
    errors.add(:bus, "debe pertenecer a la empresa") if bus && bus.company_id != company_id
    errors.add(:route, "debe pertenecer a la empresa") if route && route.company_id != company_id
  end
end
