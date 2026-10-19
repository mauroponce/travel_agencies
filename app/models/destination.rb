class Destination < ApplicationRecord
  belongs_to :company
  has_many :accommodations, dependent: :restrict_with_error
  has_many :travel_packages, dependent: :restrict_with_error
  validates :name, presence: true, uniqueness: { scope: :company_id }
end
