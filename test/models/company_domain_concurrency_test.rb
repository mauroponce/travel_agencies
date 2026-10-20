require "test_helper"

class CompanyDomainConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous primary changes are serialized and preserve one primary domain" do
    company = Company.create!(name: "Dominios concurrentes", slug: "domains-#{SecureRandom.hex(4)}")
    domains = 2.times.map do
      company.company_domains.create!(hostname: "app-#{SecureRandom.hex(3)}.example.com", kind: "custom",
        status: "active", cname_target: "tenants.example.net", verified_at: Time.current,
        tls_status: "ready", activated_at: Time.current)
    end
    ready = Queue.new
    start = Queue.new

    threads = domains.map do |domain|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          CompanyDomains::MakePrimary.call(company: Company.find(company.id),
            company_domain: CompanyDomain.find(domain.id)).id
        end
      end
    end
    domains.size.times { ready.pop }
    domains.size.times { start << true }

    assert_equal domains.map(&:id).sort, threads.map(&:value).sort
    assert_equal 1, company.company_domains.reload.where(primary: true).count
    assert_includes domains.map(&:id), company.primary_domain.id
    assert company.platform_domain.reload.active?
  end
end
