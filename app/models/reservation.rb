class Reservation < ApplicationRecord
  include CompanyAssociationIntegrity
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
  validates_same_company :departure_offer, :seller_membership
  validate :valid_status_transition, on: :update
  validate :commercial_snapshot_is_immutable, on: :update

  def total_cents
    passengers.size * (unit_price_cents.to_i + unit_fee_cents.to_i)
  end

  private

  def seller_matches_channel
    errors.add(:seller_membership, "es obligatorio para ventas de revendedor") if channel == "reseller" && seller_membership.nil?
    errors.add(:seller_membership, "debe estar vacío para venta directa") if channel == "direct" && seller_membership.present?
  end

  def valid_status_transition
    return unless will_save_change_to_status?

    from, to = status_change_to_be_saved
    allowed = { "requested" => [ "confirmed" ], "confirmed" => [ "cancelled" ], "cancelled" => [] }
    errors.add(:status, "no admite la transición #{from} → #{to}") unless allowed.fetch(from, []).include?(to)
  end

  def commercial_snapshot_is_immutable
    return unless status_in_database.in?(%w[confirmed cancelled])

    protected_fields = %w[company_id departure_offer_id seller_membership_id channel unit_price_cents unit_fee_cents minimum_payment_cents terms_snapshot]
    errors.add(:base, "La condición comercial confirmada no puede modificarse") if (changes_to_save.keys & protected_fields).any?
  end
end
