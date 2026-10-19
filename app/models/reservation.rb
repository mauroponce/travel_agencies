class Reservation < ApplicationRecord
  belongs_to :company
  belongs_to :departure_offer
  belongs_to :seller_membership, class_name: "Membership", optional: true
  belongs_to :created_by, class_name: "User"
  has_many :passengers, dependent: :destroy
  has_many :customer_payments, dependent: :restrict_with_error
  has_one :commission_entry, dependent: :restrict_with_error
  has_one :passenger_form, dependent: :nullify

  validates :code, presence: true, uniqueness: { scope: :company_id }
  validates :channel, inclusion: { in: %w[direct reseller] }
  validates :status, inclusion: { in: %w[requested confirmed cancelled] }
  validate :seller_matches_channel
  validate :records_share_company

  def total_cents
    passengers.size * (unit_price_cents.to_i + unit_fee_cents.to_i)
  end

  private

  def seller_matches_channel
    errors.add(:seller_membership, "es obligatorio para ventas de revendedor") if channel == "reseller" && seller_membership.nil?
    errors.add(:seller_membership, "debe estar vacío para venta directa") if channel == "direct" && seller_membership.present?
  end


  def records_share_company
    errors.add(:departure_offer, "debe pertenecer a la empresa") if departure_offer && departure_offer.company_id != company_id
    errors.add(:seller_membership, "debe pertenecer a la empresa") if seller_membership && seller_membership.company_id != company_id
  end
end
