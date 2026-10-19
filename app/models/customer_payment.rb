class CustomerPayment < ApplicationRecord
  include SafeAttachment
  belongs_to :company
  belongs_to :reservation
  belongs_to :recorded_by, class_name: "User"
  belongs_to :received_by_membership, class_name: "Membership", optional: true
  has_one_attached :proof
  has_many :remittance_allocations, dependent: :restrict_with_error

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :method, inclusion: { in: %w[cash transfer mercado_pago other] }
  validates :status, inclusion: { in: %w[declared partially_remitted verified voided] }
  validate -> { validate_safe_attachment(:proof) }
  validate :same_company_as_reservation

  def allocated_cents
    remittance_allocations.sum(:amount_cents)
  end

  def pending_remittance_cents
    amount_cents - allocated_cents
  end

  private

  def same_company_as_reservation
    errors.add(:reservation, "debe pertenecer a la empresa") if reservation && reservation.company_id != company_id
    if received_by_membership && received_by_membership.company_id != company_id
      errors.add(:received_by_membership, "debe pertenecer a la empresa")
    end
  end
end
