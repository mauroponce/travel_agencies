module CompanyDomains
  class MakePrimary
    def self.call(company:, company_domain:)
      new(company:, company_domain:).call
    end

    def initialize(company:, company_domain:)
      @company = company
      @company_domain = company_domain
    end

    def call
      ApplicationRecord.transaction do
        @company.lock!
        domain = @company.company_domains.lock.find(@company_domain.id)
        raise ActiveRecord::RecordInvalid, domain unless domain.active?

        now = Time.current
        @company.company_domains.where(primary: true).where.not(id: domain.id)
          .update_all(primary: false, updated_at: now)
        domain.update!(primary: true, updated_at: now) unless domain.primary?
        domain
      end
    end
  end
end
