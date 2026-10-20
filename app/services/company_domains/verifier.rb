require "resolv"
require "net/http"

module CompanyDomains
  class Verifier
    Result = Data.define(:ownership, :cname, :tls, :errors, :mode) do
      def reverification? = mode == :reverification
    end

    def self.call(company_domain, dns: Resolv::DNS, https_probe: nil)
      new(company_domain, dns:, https_probe:).call
    end

    def initialize(company_domain, dns:, https_probe:)
      @domain = company_domain
      @dns = dns
      @https_probe = https_probe || method(:https_ready?)
    end

    def call
      raise ArgumentError, "Only custom domains require verification" unless @domain.custom?

      ownership = ownership_verified?
      cname = cname_verified?
      tls = ownership && cname && @https_probe.call(@domain.hostname)
      errors = []
      errors << "Falta el TXT de propiedad" unless ownership
      errors << "El CNAME no apunta al destino técnico configurado" unless cname
      errors << "HTTPS todavía no presenta un certificado válido" if ownership && cname && !tls

      mode = persist_result(ownership:, cname:, tls:)
      Result.new(ownership:, cname:, tls:, errors:, mode:)
    end

    private

    def persist_result(ownership:, cname:, tls:)
      @domain.with_lock do
        if @domain.active?
          # DNS or certificate outages must not disable a hostname that is already
          # serving traffic. The verification attempt is still returned and audited
          # by the caller; only a complete success refreshes the last verified time.
          @domain.update!(verified_at: Time.current) if ownership && cname && tls
          :reverification
        else
          ownership_and_cname = ownership && cname
          @domain.update!(
            status: ownership_and_cname ? "verified" : "pending",
            verified_at: ownership_and_cname ? Time.current : nil,
            tls_status: tls ? "ready" : (ownership_and_cname ? "failed" : "pending")
          )
          :initial
        end
      end
    end

    def ownership_verified?
      records = resources("#{verification_label}.#{@domain.hostname}", Resolv::DNS::Resource::IN::TXT)
      records.any? do |record|
        value = record.data.to_s.delete_prefix("#{verification_value_prefix}=")
        value.present? && ActiveSupport::SecurityUtils.secure_compare(
          CompanyDomain.digest(value), @domain.verification_token_digest.to_s)
      end
    end

    def verification_label = ENV.fetch("DOMAIN_VERIFICATION_LABEL", "_tenant-verification")
    def verification_value_prefix = ENV.fetch("DOMAIN_VERIFICATION_VALUE_PREFIX", "tenant-verification")

    def cname_verified?
      expected = PlatformHosts.normalize(@domain.cname_target)
      return false if expected.blank?
      resources(@domain.hostname, Resolv::DNS::Resource::IN::CNAME)
        .any? { |record| PlatformHosts.normalize(record.name.to_s) == expected }
    end

    def resources(name, type)
      if @dns.respond_to?(:open)
        @dns.open { |resolver| resolver.getresources(name, type) }
      else
        @dns.getresources(name, type)
      end
    rescue Resolv::ResolvError, Resolv::ResolvTimeout
      []
    end

    def https_ready?(hostname)
      http = Net::HTTP.new(hostname, 443)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 5
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      response = http.request_head("/up")
      response.is_a?(Net::HTTPResponse)
    rescue IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Timeout::Error
      false
    end
  end
end
