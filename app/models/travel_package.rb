class TravelPackage < ApplicationRecord
  include SafeAttachment
  include CompanyAssociationIntegrity
  belongs_to :company
  belongs_to :destination
  has_many :departure_offers, dependent: :restrict_with_error
  has_many_attached :images
  validates :name, presence: true
  validates :days, numericality: { only_integer: true, greater_than: 0 }
  validates :nights, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates_same_company :destination
  validate -> { validate_safe_attachment(:images) }
end
