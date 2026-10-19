class Remittance < ApplicationRecord
  include SafeAttachment
  belongs_to :company
  belongs_to :reseller_membership, class_name: "Membership"
  belongs_to :declared_by, class_name: "User"
  belongs_to :verified_by, class_name: "User", optional: true
  has_many :remittance_allocations, dependent: :destroy
  has_many :customer_payments, through: :remittance_allocations
  has_one_attached :proof

  validates :code, presence: true, uniqueness: { scope: :company_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :method, inclusion: { in: %w[cash transfer mercado_pago other] }
  validates :status, inclusion: { in: %w[declared verified rejected] }
  validate -> { validate_safe_attachment(:proof) }
  validate :membership_belongs_to_company

  def verify!(user)
    transaction do
      already_verified = false
      with_lock do
        already_verified = status == "verified"
        unless already_verified
          raise ArgumentError, "Solo se verifican rendiciones declaradas" unless status == "declared"
          update!(status: "verified", verified_by: user, verified_at: Time.current)
        end
      end
      next self if already_verified

      customer_payments.order(:id).lock.each do |payment|
        verified_cents = payment.remittance_allocations.joins(:remittance).where(remittances: { status: "verified" }).sum(:amount_cents)
        payment.update!(status: verified_cents >= payment.amount_cents ? "verified" : "partially_remitted")
      end
    end
  end

  private

  def membership_belongs_to_company
    errors.add(:reseller_membership, "debe pertenecer a la empresa") if reseller_membership && reseller_membership.company_id != company_id
  end
end
