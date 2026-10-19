class CommissionRule < ApplicationRecord
  belongs_to :company
  belongs_to :reseller_membership, class_name: "Membership"
  validates :kind, inclusion: { in: %w[percentage fixed] }
  validates :status, inclusion: { in: %w[active inactive] }
  validate :membership_belongs_to_company

  def calculate(total_cents)
    kind == "fixed" ? fixed_cents.to_i : (BigDecimal(total_cents.to_s) * percentage.to_d / 100).round
  end

  private

  def membership_belongs_to_company
    errors.add(:reseller_membership, "debe pertenecer a la empresa") if reseller_membership && reseller_membership.company_id != company_id
  end
end
