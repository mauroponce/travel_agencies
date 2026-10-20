class DepartureOffer < ApplicationRecord
  include CompanyAssociationIntegrity
  belongs_to :company
  belongs_to :travel_package
  belongs_to :departure
  belongs_to :accommodation
  has_many :fare_versions, -> { order(valid_from: :desc) }, dependent: :restrict_with_error
  has_many :reservations, dependent: :restrict_with_error

  normalizes :slug, with: ->(value) { value.to_s.parameterize }
  validates :slug, presence: true, uniqueness: { scope: :company_id }
  validates :status, inclusion: { in: %w[draft published unpublished cancelled] }
  validates_same_company :travel_package, :departure, :accommodation
  validate :departure_cannot_change_with_reservations, on: :update

  scope :published, -> { where(status: "published") }

  def current_fare(at: Time.current)
    if fare_versions.loaded?
      fare_versions.select { |fare| fare.valid_from <= at && (fare.valid_until.nil? || fare.valid_until > at) }
        .max_by(&:valid_from)
    else
      fare_versions.where("valid_from <= ? AND (valid_until IS NULL OR valid_until > ?)", at, at).first
    end
  end

  delegate :available_seats, to: :departure

  private

  def departure_cannot_change_with_reservations
    return unless will_save_change_to_departure_id? && reservations.exists?

    errors.add(:departure, "no puede cambiar porque la oferta ya tiene reservas")
  end
end
