class Company < ApplicationRecord
  include SafeAttachment

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
  has_many :room_assignments, dependent: :destroy
  has_many :customer_payments, dependent: :destroy
  has_many :commission_rules, dependent: :destroy
  has_many :commission_entries, dependent: :destroy
  has_many :remittances, dependent: :destroy
  has_many :company_domains, dependent: :destroy
  has_one_attached :logo

  attr_accessor :platform_subdomain

  normalizes :slug, with: ->(value) { value.to_s.parameterize }
  validates :name, :slug, presence: true
  validates :slug, uniqueness: true
  validates :status, inclusion: { in: %w[active suspended] }
  validate :platform_subdomain_is_available, on: :create
  validate -> { validate_safe_attachment(:logo) }

  after_create :create_platform_domain!

  def primary_domain
    company_domains.active.find_by(primary: true) || company_domains.active.find_by(kind: "platform_subdomain")
  end

  def platform_domain
    company_domains.find_by(kind: "platform_subdomain")
  end

  private

  def create_platform_domain!
    hostname = PlatformHosts.platform_hostname(platform_subdomain.presence || slug)
    company_domains.create!(hostname:, kind: "platform_subdomain", status: "active", primary: true,
      tls_status: "ready", verified_at: Time.current, activated_at: Time.current)
  end

  def platform_subdomain_is_available
    value = PlatformHosts.normalize(platform_subdomain.presence || slug)
    errors.add(:platform_subdomain, "está reservado") if PlatformHosts.reserved_subdomain?(value)
    errors.add(:platform_subdomain, "no es válido") unless value.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/)
  end
end
