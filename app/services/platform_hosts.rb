module PlatformHosts
  RESERVED_SUBDOMAINS = %w[www admin auth api platform app mail smtp static assets cdn status support].freeze

  module_function

  def base_domain
    normalize(ENV.fetch("PLATFORM_BASE_DOMAIN", Rails.env.test? ? "example.test" : "lvh.me"))
  end

  def auth_host
    normalize(ENV.fetch("AUTH_HOST", "auth.#{base_domain}"))
  end

  def platform_host
    normalize(ENV.fetch("PLATFORM_HOST", "platform.#{base_domain}"))
  end

  def platform_hostname(subdomain)
    "#{normalize(subdomain)}.#{base_domain}"
  end

  def custom_domain_cname_target
    normalize(ENV.fetch("CUSTOM_DOMAIN_CNAME_TARGET", "tenants.#{base_domain}"))
  end

  def protocol
    ENV.fetch("APP_PROTOCOL", Rails.env.production? ? "https" : "http")
  end

  def port
    value = ENV["APP_PORT"].presence
    value&.to_i
  end

  def url(host:, path: "/", query: nil)
    URI::Generic.build(scheme: protocol, host: normalize(host), port:, path: path.presence || "/", query:).to_s
  end

  def normalize(hostname)
    hostname.to_s.strip.downcase.delete_suffix(".")
  end

  def reserved_subdomain?(value)
    RESERVED_SUBDOMAINS.include?(normalize(value))
  end
end
