class RemittanceAllocation < ApplicationRecord
  belongs_to :remittance
  belongs_to :customer_payment
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validate :same_company

  private

  def same_company
    return unless remittance && customer_payment
    errors.add(:base, "La rendición y el pago deben ser de la misma empresa") if remittance.company_id != customer_payment.company_id
  end
end
