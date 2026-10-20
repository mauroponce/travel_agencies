class CommissionEntry < ApplicationRecord
  include CompanyAssociationIntegrity
  belongs_to :company
  belongs_to :reservation
  belongs_to :reseller_membership, class_name: "Membership"
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[accrued payable settled] }
  validates :reservation_id, uniqueness: true
  validates_same_company :reservation, :reseller_membership
  validate :reseller_matches_reservation
  validate :financial_snapshot_is_immutable, on: :update

  private

  def reseller_matches_reservation
    return unless reservation && reseller_membership
    errors.add(:reseller_membership, "debe coincidir con la venta atribuida") if reservation.seller_membership_id != reseller_membership_id
  end

  def financial_snapshot_is_immutable
    protected_fields = %w[company_id reservation_id reseller_membership_id amount_cents calculation_kind rule_snapshot]
    changed = changes_to_save.keys & protected_fields
    errors.add(:base, "El snapshot de comisión no puede modificarse") if changed.any?
  end
end
