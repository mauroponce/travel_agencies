class CompanyUrl
  def self.call(company, path: "/", query: nil)
    domain = company.primary_domain
    raise ArgumentError, "Company #{company.id} has no active domain" unless domain

    PlatformHosts.url(host: domain.hostname, path:, query:)
  end
end
