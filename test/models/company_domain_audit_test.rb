require "test_helper"

class CompanyDomainAuditTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Auditable", slug: "auditable-#{SecureRandom.hex(3)}")
  end

  test "detects old base domains, missing primaries and unconfigured active hosts" do
    platform = @company.platform_domain
    platform.update_columns(hostname: "#{@company.slug}.old.example", primary: false)

    result = CompanyDomains::Audit.call(caddy_site_addresses: PlatformHosts.platform_host)

    assert_includes result.errors.map(&:code), :base_domain_mismatch
    assert_includes result.errors.map(&:code), :invalid_primary
    assert_includes result.warnings.map(&:code), :host_missing_from_caddy
  end

  test "detects invalid custom domains and stale CNAME targets" do
    custom = @company.company_domains.create!(hostname: "custom.example.net", kind: "custom", status: "pending",
      cname_target: PlatformHosts.custom_domain_cname_target)
    custom.update_columns(hostname: "nested.#{PlatformHosts.base_domain}", cname_target: "old-target.example.net")

    result = CompanyDomains::Audit.call(caddy_site_addresses: @company.platform_domain.hostname)

    assert_includes result.errors.map(&:code), :invalid_custom_domain
    assert_includes result.warnings.map(&:code), :stale_cname_target
  end

  test "base domain migration plans and applies without touching company data" do
    CompanyDomain.where(kind: "platform_subdomain").includes(:company).find_each do |domain|
      domain.update_columns(hostname: "#{domain.company.slug}.example.test")
    end
    original_host = @company.platform_domain.reload.hostname
    new_base = "next.example.test"

    plan = CompanyDomains::BaseDomainMigration.plan(from: PlatformHosts.base_domain, to: new_base)
    mapping = plan.mappings.find { |item| item.domain_id == @company.platform_domain.id }
    assert plan.safe?, plan.errors.join("; ")
    assert_equal "#{@company.slug}.#{new_base}", mapping.to

    with_environment("PLATFORM_BASE_DOMAIN", new_base) do
      applied = CompanyDomains::BaseDomainMigration.apply!(from: "example.test", to: new_base)
      assert applied.safe?, applied.errors.join("; ")
      assert_equal "#{@company.slug}.#{new_base}", @company.platform_domain.reload.hostname
      assert_equal @company.name, @company.reload.name
    end

    with_environment("PLATFORM_BASE_DOMAIN", "example.test") do
      CompanyDomains::BaseDomainMigration.apply!(from: new_base, to: "example.test")
    end
    assert_equal original_host, @company.platform_domain.reload.hostname
  end

  private

  def with_environment(name, value)
    previous = ENV[name]
    ENV[name] = value
    yield
  ensure
    ENV[name] = previous
  end
end
