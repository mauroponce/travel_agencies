class CommissionRule < ApplicationRecord
  include CompanyAssociationIntegrity
  belongs_to :company
  belongs_to :reseller_membership, class_name: "Membership"
  validates :kind, inclusion: { in: %w[percentage fixed] }
  validates :status, inclusion: { in: %w[active inactive] }
  validates_same_company :reseller_membership
  validate :membership_is_reseller

  def calculate(total_cents)
    kind == "fixed" ? fixed_cents.to_i : (BigDecimal(total_cents.to_s) * percentage.to_d / 100).round
  end

  private

  def membership_is_reseller
    errors.add(:reseller_membership, "debe tener perfil revendedor") if reseller_membership && !reseller_membership.role?("reseller")
  end
end
