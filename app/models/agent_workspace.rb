class AgentWorkspace < ApplicationRecord
  belongs_to :owner, class_name: "User", optional: true
  has_one :hostname_registration, dependent: :restrict_with_error
  has_many :agent_suppliers, dependent: :restrict_with_error
  has_many :agent_trips, dependent: :restrict_with_error
  has_many :agent_trip_revisions, dependent: :restrict_with_error
  has_many :agent_imports, dependent: :restrict_with_error
  has_many :agent_searches, dependent: :restrict_with_error
  has_many :agent_ai_executions, dependent: :restrict_with_error
  has_one_attached :about_photo
  validates :about_text, length: { maximum: 1200, message: "debe tener hasta 1200 caracteres" }
  normalizes :subdomain, with: ->(value) { PlatformHosts.normalize(value) }
  normalizes :slug, with: ->(value) { PlatformHosts.normalize(value) }
  normalizes :whatsapp, with: ->(value) { value.to_s.gsub(/[^0-9]/, "") }
  before_validation :assign_initial_slug, on: :create
  validates :business_name, :public_name, :whatsapp, :slug, presence: true
  normalizes :invited_email, with: ->(value) { value.to_s.strip.downcase.presence }
  validates :subdomain, uniqueness: true, allow_blank: true
  validates :slug, uniqueness: { message: "ya está en uso; elegí otro o usá la sugerencia" },
    format: { with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/, message: "debe tener hasta 63 letras minúsculas, números o guiones" }
  validates :owner_id, uniqueness: true, allow_nil: true
  validates :invited_email, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validate { errors.add(:owner, "requiere un propietario o correo invitado") if owner_id.nil? && invited_email.blank? }
  validates :whatsapp, format: { with: /\A[1-9]\d{7,14}\z/ }
  validates :subdomain, format: { with: /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/ }, allow_blank: true
  validates :status, inclusion: { in: %w[active suspended] }
  validates :plan, inclusion: { in: %w[agent_pilot] }
  validate do
    errors.add(:slug, "está reservado; elegí otro o usá la sugerencia") if self.class.reserved_slug?(slug)
    errors.add(:slug, "es permanente una vez creada tu web") if persisted? && will_save_change_to_slug?
    errors.add(:subdomain, "está reservado") if subdomain.present? && (PlatformHosts.reserved_subdomain?(subdomain) || [ PlatformHosts.auth_host, PlatformHosts.platform_host, PlatformHosts.custom_domain_cname_target ].include?(hostname))
    errors.add(:timezone, "no es válida") unless ActiveSupport::TimeZone[timezone]
    errors.add(:subdomain, "es permanente durante el MVP") if persisted? && will_save_change_to_subdomain?
    if new_record? && subdomain.present? && (HostnameRegistration.exists?(hostname:) || CompanyDomain.exists?(hostname:))
      errors.add(:subdomain, "ya está en uso")
    end
  end
  after_create { create_hostname_registration!(hostname:) if subdomain.present? }

  RESERVED_SLUGS = (PlatformHosts::RESERVED_SUBDOMAINS + %w[
    agente auth up manifest service-worker session test onboarding context dashboard
    paquetes salidas ofertas reservas solicitudes pagos rendiciones notificaciones
    push_subscriptions catalogos equipo comisiones viajes formularios internal
    rails cable brand icon favicon robots
  ]).freeze

  def name = business_name

  def name=(value)
    self.business_name = self.public_name = value.to_s.strip
  end

  def self.reserved_slug?(value) = RESERVED_SLUGS.include?(value)

  def self.slug_available?(value)
    value.to_s.match?(/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/) &&
      !reserved_slug?(value) && !exists?(slug: value)
  end

  def self.suggest_slug(name)
    base = name.to_s.parameterize.first(63).sub(/-+\z/, "").presence || "agente"
    candidate = base
    suffix = 1
    until slug_available?(candidate)
      suffix += 1
      ending = "-#{suffix}"
      candidate = "#{base.first(63 - ending.length).sub(/-+\z/, '')}#{ending}"
    end
    candidate
  end

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
  def hostname = (PlatformHosts.platform_hostname(subdomain) if subdomain.present?)
  def url(path: nil) = PlatformHosts.url(host: PlatformHosts.platform_host, path: path || "/#{slug}")

  private

  def assign_initial_slug
    self.slug = self.class.suggest_slug(subdomain.presence || name) if slug.nil?
  end
end
