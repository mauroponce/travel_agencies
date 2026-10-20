class CompanyDomain < ApplicationRecord
  KINDS = %w[platform_subdomain custom].freeze
  STATUSES = %w[pending verified active disabled].freeze
  TLS_STATUSES = %w[pending ready failed].freeze
  HOSTNAME_PATTERN = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

  belongs_to :company

  normalizes :hostname, with: ->(value) { PlatformHosts.normalize(value) }
  validates :hostname, presence: true, uniqueness: { case_sensitive: false }, format: { with: HOSTNAME_PATTERN }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :tls_status, inclusion: { in: TLS_STATUSES }
  validate :platform_subdomain_is_valid
  validate :custom_domain_is_external
  validate :active_custom_domain_is_verified
  validate :primary_domain_is_active

  scope :active, -> { where(status: "active") }
  scope :resolvable, -> { active.joins(:company).where(companies: { status: "active" }) }

  before_destroy :preserve_platform_subdomain

  def self.find_resolvable(hostname)
    resolvable.find_by("lower(hostname) = ?", PlatformHosts.normalize(hostname))
  end

  def platform_subdomain? = kind == "platform_subdomain"
  def custom? = kind == "custom"
  def active? = status == "active"

  def issue_verification_token!
    token = SecureRandom.urlsafe_base64(24)
    update!(verification_token_digest: self.class.digest(token), status: "pending", verified_at: nil,
      activated_at: nil, disabled_at: nil, primary: false, tls_status: "pending")
    token
  end

  def self.digest(value) = Digest::SHA256.hexdigest(value.to_s)

  private

  def platform_subdomain_is_valid
    return unless platform_subdomain?

    suffix = ".#{PlatformHosts.base_domain}"
    label = hostname.to_s.delete_suffix(suffix)
    errors.add(:hostname, "debe pertenecer al dominio base configurado") unless hostname.to_s.end_with?(suffix) && !label.include?(".")
    errors.add(:hostname, "usa un subdominio reservado") if PlatformHosts.reserved_subdomain?(label)
  end

  def active_custom_domain_is_verified
    return unless custom? && active?
    errors.add(:status, "requiere propiedad verificada") if verified_at.blank?
    errors.add(:tls_status, "debe estar listo antes de activar") unless tls_status == "ready"
  end

  def custom_domain_is_external
    return unless custom?
    errors.add(:hostname, "está reservado para la infraestructura") if
      [ PlatformHosts.auth_host, PlatformHosts.platform_host ].include?(hostname) ||
        hostname.to_s.end_with?(".#{PlatformHosts.base_domain}")
    errors.add(:cname_target, "es obligatorio") if cname_target.blank?
  end

  def primary_domain_is_active
    errors.add(:primary, "requiere un dominio activo") if primary? && !active?
  end

  def preserve_platform_subdomain
    return unless platform_subdomain?
    errors.add(:base, "El subdominio de plataforma es permanente")
    throw :abort
  end
end
