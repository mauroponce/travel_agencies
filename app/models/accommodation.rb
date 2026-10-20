class Accommodation < ApplicationRecord
  include SafeAttachment
  include CompanyAssociationIntegrity
  belongs_to :company
  belongs_to :destination
  has_many_attached :photos
  validates :name, presence: true
  validates_same_company :destination
  validate -> { validate_safe_attachment(:photos) }
end
