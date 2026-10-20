class CustomerPayment < ApplicationRecord
  include SafeAttachment
  include CompanyAssociationIntegrity
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
  validates_same_company :reservation, :received_by_membership

  def allocated_cents
    if remittance_allocations.loaded?
      remittance_allocations.sum { |allocation| allocation.remittance.status == "rejected" ? 0 : allocation.amount_cents }
    else
      remittance_allocations.joins(:remittance).where.not(remittances: { status: "rejected" }).sum(:amount_cents)
    end
  end

  def pending_remittance_cents
    amount_cents - allocated_cents
  end
end
