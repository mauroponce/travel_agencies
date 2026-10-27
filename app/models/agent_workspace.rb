class AgentWorkspace < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true
  has_one :hostname_registration, dependent: :restrict_with_error
  has_many :agent_suppliers, dependent: :restrict_with_error
  has_many :agent_trips, dependent: :restrict_with_error
  has_many :agent_trip_revisions, dependent: :restrict_with_error
  has_many :agent_imports, dependent: :restrict_with_error
  has_many :agent_searches, dependent: :restrict_with_error
  has_many :agent_ai_executions, dependent: :restrict_with_error
  normalizes :subdomain, with: ->(value) { PlatformHosts.normalize(value) }
  normalizes :whatsapp, with: ->(value) { value.to_s.gsub(/[^0-9]/, "") }
  validates :business_name, :public_name, :whatsapp, :subdomain, presence: true
  normalizes :invited_email, with: ->(value) { value.to_s.strip.downcase.presence }
  validates :subdomain, uniqueness: true
  validates :owner_id, uniqueness: true, allow_nil: true
  validates :invited_email, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validate { errors.add(:owner, "requiere un propietario o correo invitado") if owner_id.nil? && invited_email.blank? }
  validates :whatsapp, format: { with: /\A[1-9]\d{7,14}\z/ }
  validates :subdomain, format: { with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/ }
  validates :status, inclusion: { in: %w[active suspended] }
  validates :plan, inclusion: { in: %w[agent_pilot] }
  validate do
    errors.add(:subdomain, "está reservado") if PlatformHosts.reserved_subdomain?(subdomain) || [ PlatformHosts.auth_host, PlatformHosts.platform_host, PlatformHosts.custom_domain_cname_target ].include?(hostname)
    errors.add(:timezone, "no es válida") unless ActiveSupport::TimeZone[timezone]
    errors.add(:subdomain, "es permanente durante el MVP") if persisted? && will_save_change_to_subdomain?
    if new_record? && (HostnameRegistration.exists?(hostname:) || CompanyDomain.exists?(hostname:))
      errors.add(:subdomain, "ya está en uso")
    end
  end
  after_create { create_hostname_registration!(hostname:) }

  # Self-service registration follows the same rollout and hostname integrity
  # checks as agent workspaces, including in staging and production.
  def self.self_signup_enabled? = enabled?

  def self.enabled?
    configured = ENV.fetch("AGENT_ENABLED", Rails.env.local? ? "true" : "false") == "true"
    configured && (Rails.env.local? || connection.foreign_key_exists?(:company_domains, name: "fk_company_domain_registered_host"))
  end
  # Called only after Google has verified the identity, inside the OAuth transaction.
  def accept_invitation!(user)
    with_lock do
      return owner_id == user.id if owner_id
      return false unless active? && invited_email&.casecmp?(user.email)
      return false if user.agent_workspace
      update!(owner: user)
      true
    end
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def active? = status == "active"
  def hostname = PlatformHosts.platform_hostname(subdomain)
  def url(path: "/") = PlatformHosts.url(host: hostname_registration.hostname, path:)
end
