class AuthenticationCode < ApplicationRecord
  belongs_to :authentication_request
  belongs_to :user
  belongs_to :company, optional: true
  belongs_to :membership, optional: true

  validates :target_hostname, :token_digest, :browser_nonce_digest, :expires_at, presence: true
  validates :token_digest, uniqueness: true
  validate :scope_is_consistent

  def self.issue!(authentication_request:, user:, membership:, expires_in: 2.minutes)
    token = SecureRandom.urlsafe_base64(32)
    code = create!(authentication_request:, user:, company: authentication_request.company, membership:,
      target_hostname: authentication_request.return_hostname, token_digest: digest(token),
      browser_nonce_digest: authentication_request.browser_nonce_digest, expires_at: expires_in.from_now)
    [ code, token ]
  end

  def self.find_by_token(token) = find_by(token_digest: digest(token))
  def available? = consumed_at.nil? && expires_at.future?
  def self.digest(value) = Digest::SHA256.hexdigest(value.to_s)

  private

  def scope_is_consistent
    errors.add(:membership, "no coincide con la empresa") unless company_id.present? == membership_id.present?
    errors.add(:membership, "pertenece a otra empresa") if membership && membership.company_id != company_id
    errors.add(:authentication_request, "pertenece a otra empresa") if authentication_request.company_id != company_id
  end
end
