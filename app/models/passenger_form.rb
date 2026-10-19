class PassengerForm < ApplicationRecord
  belongs_to :company
  belongs_to :departure_offer
  belongs_to :reseller_membership, class_name: "Membership"
  belongs_to :reservation, optional: true
  has_one :passenger_form_submission, dependent: :destroy
  validate :records_share_company

  scope :available, -> { where(submitted_at: nil, revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(company:, departure_offer:, reseller_membership:, prefilled_name: nil, expires_in: 7.days)
    token = SecureRandom.urlsafe_base64(32)
    form = create!(company:, departure_offer:, reseller_membership:, prefilled_name:,
      expires_at: expires_in.from_now, token_digest: Digest::SHA256.hexdigest(token))
    [ form, token ]
  end

  def self.find_by_token(token)
    find_by(token_digest: Digest::SHA256.hexdigest(token.to_s))
  end

  def available?
    submitted_at.nil? && revoked_at.nil? && expires_at.future?
  end

  private

  def records_share_company
    errors.add(:departure_offer, "debe pertenecer a la empresa") if departure_offer && departure_offer.company_id != company_id
    errors.add(:reseller_membership, "debe pertenecer a la empresa") if reseller_membership && reseller_membership.company_id != company_id
  end
end
