class Accommodation < ApplicationRecord
  include SafeAttachment
  belongs_to :company
  belongs_to :destination
  has_many_attached :photos
  validates :name, presence: true
  validate :same_company_as_destination
  validate -> { validate_safe_attachment(:photos) }

  private

  def same_company_as_destination
    errors.add(:destination, "debe pertenecer a la empresa") if destination && destination.company_id != company_id
  end
end
