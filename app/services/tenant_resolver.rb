class TenantResolver
  class UnknownHost < StandardError; end
  class SuspendedCompany < StandardError; end

  Result = Data.define(:scope, :company, :company_domain)

  def self.call(hostname)
    host = PlatformHosts.normalize(hostname)
    return Result.new(scope: :auth, company: nil, company_domain: nil) if host == PlatformHosts.auth_host
    return Result.new(scope: :platform, company: nil, company_domain: nil) if host == PlatformHosts.platform_host

    domain = CompanyDomain.find_by("lower(hostname) = ?", host)
    raise UnknownHost if domain.nil? || !domain.active?
    raise SuspendedCompany unless domain.company.status == "active"

    Result.new(scope: :tenant, company: domain.company, company_domain: domain)
  end
end
