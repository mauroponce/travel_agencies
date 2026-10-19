class Departure < ApplicationRecord
  belongs_to :company
  belongs_to :bus
  belongs_to :route, optional: true
  has_many :departure_stops, -> { order(:position) }, dependent: :destroy
  has_many :departure_offers, dependent: :restrict_with_error
  has_many :seat_allocations, dependent: :restrict_with_error
  has_many :departure_assignments, dependent: :destroy
  accepts_nested_attributes_for :departure_stops, update_only: true

  validates :code, presence: true, uniqueness: { scope: :company_id }
  validates :capacity, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: %w[draft open sold_out cancelled completed] }
  validate :catalog_records_share_company
  validate :capacity_covers_occupied_seats

  def occupied_seats
    seat_allocations.where(status: "active").count
  end

  def available_seats
    [ capacity - occupied_seats, 0 ].max
  end

  def update_with_inventory_lock(attributes)
    with_lock { update(attributes) }
  end

  private

  def catalog_records_share_company
    errors.add(:bus, "debe pertenecer a la empresa") if bus && bus.company_id != company_id
    errors.add(:route, "debe pertenecer a la empresa") if route && route.company_id != company_id
  end

  def capacity_covers_occupied_seats
    return unless capacity && persisted?

    errors.add(:capacity, "no puede ser menor que los asientos ocupados") if capacity < occupied_seats
  end
end
