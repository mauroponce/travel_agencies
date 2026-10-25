class TenantResolver
  class UnknownHost < StandardError; end
  class SuspendedCompany < StandardError; end

  Result = Struct.new(:scope, :company, :company_domain, :agent_workspace, keyword_init: true)

  def self.call(hostname)
    host = PlatformHosts.normalize(hostname)
    return Result.new(scope: :auth, company: nil, company_domain: nil) if host == PlatformHosts.auth_host
    return Result.new(scope: :platform, company: nil, company_domain: nil) if host == PlatformHosts.platform_host

    if AgentWorkspace.enabled?
      registration = HostnameRegistration.includes(:agent_workspace).find_by(hostname: host)
      if registration&.agent_workspace
        raise UnknownHost unless registration.agent_workspace.active? && registration.hostname == registration.agent_workspace.hostname
        return Result.new(scope: :agent, agent_workspace: registration.agent_workspace)
      end
    end

    domain = CompanyDomain.find_by("lower(hostname) = ?", host)
    raise UnknownHost if domain.nil? || !domain.active?
    raise SuspendedCompany unless domain.company.status == "active"

    Result.new(scope: :tenant, company: domain.company, company_domain: domain)
  end
end
