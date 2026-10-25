require "set"

module CompanyDomains
  class Audit
    Finding = Data.define(:severity, :code, :message)
    Result = Data.define(:findings) do
      def errors = findings.select { |finding| finding.severity == :error }
      def warnings = findings.select { |finding| finding.severity == :warning }
      def ok? = errors.empty?
    end

    def self.call(caddy_site_addresses: ENV["CADDY_SITE_ADDRESSES"])
      new(caddy_site_addresses:).call
    end

    def initialize(caddy_site_addresses:)
      @configured_hosts = caddy_site_addresses.to_s.split(",").map { |host| PlatformHosts.normalize(host) }.to_set
      @findings = []
    end

    def call
      detect_duplicates
      Company.includes(:company_domains).find_each { |company| audit_company(company) }
      Agent::IntegrityAudit.call.each { |finding| add(:error, :agent_integrity, finding) }
      Result.new(findings: @findings)
    end

    private

    def detect_duplicates
      CompanyDomain.group(Arel.sql("lower(hostname)")).having("count(*) > 1").count.each do |hostname, count|
        add(:error, :duplicate_hostname, "#{hostname} está registrado #{count} veces")
      end
    end

    def audit_company(company)
      domains = company.company_domains.to_a
      platform_domains = domains.select(&:platform_subdomain?)
      active_primary = domains.select { |domain| domain.primary? && domain.active? }

      unless platform_domains.one? && platform_domains.first.active?
        add(:error, :missing_platform_subdomain, "#{company.name} no tiene exactamente un subdominio permanente activo")
      end
      add(:error, :invalid_primary, "#{company.name} no tiene exactamente un dominio principal activo") unless active_primary.one?

      domains.each do |domain|
        audit_platform_domain(company, domain) if domain.platform_subdomain?
        audit_custom_domain(company, domain) if domain.custom?
        audit_infrastructure(company, domain) if domain.active?
      end
    end

    def audit_platform_domain(company, domain)
      suffix = ".#{PlatformHosts.base_domain}"
      label = domain.hostname.to_s.delete_suffix(suffix)
      return if domain.hostname.to_s.end_with?(suffix) && !label.include?(".") && !PlatformHosts.reserved_subdomain?(label)

      add(:error, :base_domain_mismatch,
        "#{company.name}: #{domain.hostname} no pertenece al dominio base #{PlatformHosts.base_domain}")
    end

    def audit_custom_domain(company, domain)
      internal = [ PlatformHosts.platform_host, PlatformHosts.auth_host ].include?(domain.hostname) ||
        domain.hostname.to_s.end_with?(".#{PlatformHosts.base_domain}")
      unless domain.hostname.to_s.match?(CompanyDomain::HOSTNAME_PATTERN) && !internal
        add(:error, :invalid_custom_domain, "#{company.name}: #{domain.hostname} no es un dominio personalizado válido")
      end
      if domain.cname_target.blank?
        add(:error, :missing_cname_target, "#{company.name}: #{domain.hostname} no tiene destino CNAME")
      elsif PlatformHosts.normalize(domain.cname_target) != PlatformHosts.custom_domain_cname_target
        add(:warning, :stale_cname_target,
          "#{company.name}: #{domain.hostname} conserva CNAME #{domain.cname_target}; configurado #{PlatformHosts.custom_domain_cname_target}")
      end
      if domain.active? && (domain.verified_at.blank? || domain.tls_status != "ready")
        add(:error, :unverified_active_custom_domain,
          "#{company.name}: #{domain.hostname} está activo sin verificación DNS/TLS completa")
      end
    end

    def audit_infrastructure(company, domain)
      return if @configured_hosts.include?(domain.hostname)

      add(:warning, :host_missing_from_caddy,
        "#{company.name}: #{domain.hostname} está activo pero no figura en CADDY_SITE_ADDRESSES")
    end

    def add(severity, code, message)
      @findings << Finding.new(severity:, code:, message:)
    end
  end
end
