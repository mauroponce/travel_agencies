class DepartureOffer < ApplicationRecord
  belongs_to :company
  belongs_to :travel_package
  belongs_to :departure
  belongs_to :accommodation
  has_many :fare_versions, -> { order(valid_from: :desc) }, dependent: :restrict_with_error
  has_many :reservations, dependent: :restrict_with_error

  normalizes :slug, with: ->(value) { value.to_s.parameterize }
  validates :slug, presence: true, uniqueness: { scope: :company_id }
  validates :status, inclusion: { in: %w[draft published unpublished cancelled] }
  validate :all_records_share_company

  scope :published, -> { where(status: "published") }

  def current_fare(at: Time.current)
    fare_versions.where("valid_from <= ? AND (valid_until IS NULL OR valid_until > ?)", at, at).first
  end

  delegate :available_seats, to: :departure

  private

  def all_records_share_company
    [ travel_package, departure, accommodation ].compact.each do |record|
      errors.add(:base, "Todos los registros deben pertenecer a la empresa") if record.company_id != company_id
    end
  end
end
