module CompanyDomains
  class BaseDomainMigration
    class Unsafe < StandardError; end

    Mapping = Struct.new(:domain_id, :company_id, :from, :to, :agent_workspace_id, keyword_init: true)
    Plan = Data.define(:mappings, :errors) do
      def safe? = errors.empty?
    end

    def self.plan(from:, to:)
      new(from:, to:).plan
    end

    def self.apply!(from:, to:)
      new(from:, to:).apply!
    end

    def initialize(from:, to:)
      @from = PlatformHosts.normalize(from)
      @to = PlatformHosts.normalize(to)
    end

    def plan
      errors = []
      mappings = CompanyDomain.where(kind: "platform_subdomain").order(:company_id, :id).filter_map do |domain|
        suffix = ".#{@from}"
        unless domain.hostname.end_with?(suffix)
          errors << "#{domain.hostname} no pertenece al dominio de origen #{@from}"
          next
        end
        label = domain.hostname.delete_suffix(suffix)
        target = "#{label}.#{@to}"
        conflict = HostnameRegistration.where(hostname: target).exists? || CompanyDomain.where("lower(hostname) = ?", target).where.not(id: domain.id).exists?
        errors << "#{target} ya está registrado" if conflict
        Mapping.new(domain_id: domain.id, company_id: domain.company_id, from: domain.hostname, to: target)
      end
      HostnameRegistration.where.not(agent_workspace_id: nil).find_each do |registration|
        suffix = ".#{@from}"
        unless registration.hostname.end_with?(suffix)
          errors << "#{registration.hostname} no pertenece al dominio de origen #{@from}"
          next
        end
        target = "#{registration.hostname.delete_suffix(suffix)}.#{@to}"
        errors << "#{target} ya está registrado" if HostnameRegistration.where(hostname: target).where.not(id: registration.id).exists?
        mappings << Mapping.new(from: registration.hostname, to: target, agent_workspace_id: registration.agent_workspace_id)
      end
      errors << "no hay subdominios permanentes para migrar" if mappings.empty?

      active_hosts = mappings.map(&:from)
      active_transfers = AuthenticationRequest.where(return_hostname: active_hosts, used_at: nil)
        .where("expires_at > ?", Time.current).count
      active_codes = AuthenticationCode.where(target_hostname: active_hosts, consumed_at: nil)
        .where("expires_at > ?", Time.current).count
      active_transfers += active_codes
      errors << "hay #{active_transfers} autenticaciones en curso; esperá a que venzan" if active_transfers.positive?
      Plan.new(mappings:, errors: errors.uniq)
    end

    def apply!
      unless PlatformHosts.base_domain == @to
        raise Unsafe, "PLATFORM_BASE_DOMAIN debe ser #{@to} antes de aplicar esta migración"
      end

      ApplicationRecord.transaction do
        CompanyDomain.where(kind: "platform_subdomain").lock.load
        HostnameRegistration.where.not(agent_workspace_id: nil).lock.load
        current_plan = plan
        raise Unsafe, current_plan.errors.join("; ") unless current_plan.safe?

        now = Time.current
        current_plan.mappings.each do |mapping|
          if mapping.agent_workspace_id
            HostnameRegistration.find_by!(agent_workspace_id: mapping.agent_workspace_id, hostname: mapping.from).update!(hostname: mapping.to)
          else
            HostnameRegistration.reserve_company!(mapping.to, mapping.company_id)
            CompanyDomain.where(id: mapping.domain_id, hostname: mapping.from).update_all(hostname: mapping.to, updated_at: now)
            HostnameRegistration.where(hostname: mapping.from, company_id: mapping.company_id).delete_all
          end
        end
        current_plan.mappings.each { |mapping| CompanyDomain.find(mapping.domain_id).validate! if mapping.domain_id }
        current_plan
      end
    end
  end
end
