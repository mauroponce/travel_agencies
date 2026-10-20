class DepartureAssignment < ApplicationRecord
  belongs_to :departure
  belongs_to :membership
  validates :membership_id, uniqueness: { scope: :departure_id }
  validate :coordinator_membership

  private

  def coordinator_membership
    errors.add(:membership, "debe ser coordinador activo de la empresa") unless membership&.company_id == departure&.company_id && membership&.role?("coordinator")
  end
end
