class CommissionEntry < ApplicationRecord
  belongs_to :company
  belongs_to :reservation
  belongs_to :reseller_membership, class_name: "Membership"
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[accrued payable settled] }
  validates :reservation_id, uniqueness: true
  validate :records_share_company

  private

  def records_share_company
    errors.add(:reservation, "debe pertenecer a la empresa") if reservation && reservation.company_id != company_id
    errors.add(:reseller_membership, "debe pertenecer a la empresa") if reseller_membership && reseller_membership.company_id != company_id
  end
end
