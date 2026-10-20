module Platform
  class CompanyDomainsController < ApplicationController
    before_action :require_operator
    before_action :set_company
    before_action :set_domain, except: :create

    def create
      domain = @company.company_domains.create!(hostname: domain_params[:hostname], kind: "custom",
        status: "pending", cname_target: PlatformHosts.custom_domain_cname_target)
      token = domain.issue_verification_token!
      AuditRecorder.call(action: "company_domain.created", auditable: domain, actor: current_user, company: @company)
      label = ENV.fetch("DOMAIN_VERIFICATION_LABEL", "_tenant-verification")
      prefix = ENV.fetch("DOMAIN_VERIFICATION_VALUE_PREFIX", "tenant-verification")
      redirect_to platform_companies_path,
        notice: "Dominio registrado. Creá TXT #{label}.#{domain.hostname} con valor #{prefix}=#{token}."
    end

    def verify
      raise Pundit::NotAuthorizedError unless @domain.custom?
      result = CompanyDomains::Verifier.call(@domain)
      AuditRecorder.call(action: "company_domain.verified", auditable: @domain, actor: current_user,
        company: @company,
        changeset: { ownership: result.ownership, cname: result.cname, tls: result.tls, mode: result.mode })
      notice = if result.errors.empty?
        "DNS, propiedad y HTTPS verificados."
      elsif result.reverification?
        "La reverificación falló, pero el dominio continúa activo. #{result.errors.join(' ')}"
      else
        result.errors.join(" ")
      end
      redirect_to platform_companies_path,
        notice:
    end

    def activate
      raise ActiveRecord::RecordInvalid, @domain unless @domain.status == "verified" && @domain.tls_status == "ready"
      @domain.update!(status: "active", activated_at: Time.current, disabled_at: nil)
      audit("company_domain.activated")
      redirect_to platform_companies_path, notice: "Dominio activado."
    end

    def make_primary
      @domain = CompanyDomains::MakePrimary.call(company: @company, company_domain: @domain)
      audit("company_domain.primary_changed")
      redirect_to platform_companies_path, notice: "Dominio principal actualizado."
    end

    def disable
      raise Pundit::NotAuthorizedError if @domain.platform_subdomain?
      ApplicationRecord.transaction do
        @company.lock!
        @domain = @company.company_domains.lock.find(@domain.id)
        @domain.update!(status: "disabled", primary: false, disabled_at: Time.current)
        platform_domain = @company.platform_domain
        platform_domain.update!(primary: true) unless @company.company_domains.active.exists?(primary: true)
      end
      audit("company_domain.disabled")
      redirect_to platform_companies_path, notice: "Dominio deshabilitado; el subdominio permanente continúa disponible."
    end

    private

    def require_operator
      raise Pundit::NotAuthorizedError unless current_user.platform_operator?
    end
    def set_company = @company = Company.find(params[:company_id])
    def set_domain = @domain = @company.company_domains.find(params[:id])
    def domain_params = params.expect(company_domain: [ :hostname ])

    def audit(action)
      AuditRecorder.call(action:, auditable: @domain, actor: current_user, company: @company,
        changeset: { hostname: @domain.hostname, status: @domain.status, primary: @domain.primary })
    end
  end
end
