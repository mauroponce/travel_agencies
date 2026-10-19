class Company < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :destinations, dependent: :destroy
  has_many :accommodations, dependent: :destroy
  has_many :buses, dependent: :destroy
  has_many :boarding_points, dependent: :destroy
  has_many :routes, dependent: :destroy
  has_many :travel_packages, dependent: :destroy
  has_many :departures, dependent: :destroy
  has_many :departure_offers, dependent: :destroy
  has_many :reservations, dependent: :destroy
  has_many :seat_allocations, dependent: :destroy
  has_many :commission_rules, dependent: :destroy
  has_many :remittances, dependent: :destroy

  normalizes :slug, with: ->(value) { value.to_s.parameterize }
  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[active suspended] }
end
