class FareVersion < ApplicationRecord
  belongs_to :departure_offer
  belongs_to :created_by, class_name: "User", optional: true
  validates :price_cents, :service_fee_cents, :deposit_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :deposit_type, inclusion: { in: %w[fixed full] }
  validate :deposit_does_not_exceed_total

  def total_cents
    price_cents + service_fee_cents
  end

  def required_payment_cents
    deposit_type == "full" ? total_cents : deposit_cents
  end

  private

  def deposit_does_not_exceed_total
    errors.add(:deposit_cents, "no puede superar el total") if deposit_cents.to_i > total_cents
  end
end
