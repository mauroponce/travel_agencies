class AuthenticationRequest < ApplicationRecord
  belongs_to :company, optional: true
  belongs_to :company_domain, optional: true
  belongs_to :agent_workspace, optional: true
  has_many :authentication_codes, dependent: :delete_all

  validates :return_hostname, :token_digest, :browser_nonce_digest, :expires_at, presence: true
  validates :token_digest, uniqueness: true
  validate :scope_is_consistent

  def self.issue!(company:, company_domain:, return_hostname:, browser_nonce:, agent_workspace: nil, purpose: nil, expires_in: 10.minutes)
    token = SecureRandom.urlsafe_base64(32)
    purpose ||= company ? "company" : (agent_workspace ? "agent" : "operator")
    request = create!(company:, company_domain:, agent_workspace:, purpose:, return_hostname: PlatformHosts.normalize(return_hostname),
      token_digest: digest(token), browser_nonce_digest: digest(browser_nonce), expires_at: expires_in.from_now)
    [ request, token ]
  end

  def self.find_available(token)
    where(used_at: nil).where("expires_at > ?", Time.current).find_by(token_digest: digest(token))
  end

  def available? = used_at.nil? && expires_at.future?
  def self.digest(value) = Digest::SHA256.hexdigest(value.to_s)

  # Read requests/codes issued by the preceding release during a rolling deploy.
  def purpose = self[:purpose] || (company_id ? "company" : "operator")

  private

  def scope_is_consistent
    errors.add(:company, "no coincide con el dominio") unless company_id.present? == company_domain_id.present?
    errors.add(:company_domain, "pertenece a otra empresa") if company_domain && company_domain.company_id != company_id
    errors.add(:purpose, "no es válido") unless %w[company agent operator agent_onboarding].include?(purpose)
    errors.add(:agent_workspace, "no corresponde al propósito") unless (purpose == "agent") == agent_workspace_id.present?
    errors.add(:company, "no corresponde al propósito") unless (purpose == "company") == company_id.present?
    expected_host = company_domain&.hostname || agent_workspace&.hostname_registration&.hostname || PlatformHosts.platform_host
    errors.add(:return_hostname, "no coincide con el destino autorizado") if return_hostname != expected_host
  end
end
