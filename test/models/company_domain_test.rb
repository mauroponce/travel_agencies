require "test_helper"

class CompanyDomainTest < ActiveSupport::TestCase
  setup do
    @company = Company.create!(name: "Agencia Dominio", slug: "agencia-#{SecureRandom.hex(3)}")
  end

  test "platform subdomain is permanent, normalized and globally unique" do
    domain = @company.platform_domain
    assert_equal domain.hostname.downcase, domain.hostname
    assert domain.primary?
    assert_not domain.destroy

    other = Company.create!(name: "Otra", slug: "otra-#{SecureRandom.hex(3)}")
    duplicate = other.company_domains.build(hostname: domain.hostname.upcase, kind: "custom",
      cname_target: "tenants.example.net")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:hostname], "ya está en uso"
  end

  test "reserved platform subdomains and infrastructure hosts are rejected" do
    company = Company.new(name: "Reservada", slug: "reservada-#{SecureRandom.hex(2)}", platform_subdomain: "auth")
    assert_not company.valid?
    assert_includes company.errors[:platform_subdomain], "está reservado"

    custom = @company.company_domains.build(hostname: PlatformHosts.auth_host, kind: "custom",
      cname_target: "tenants.example.net")
    assert_not custom.valid?
    assert_includes custom.errors[:hostname], "está reservado para la infraestructura"
  end

  test "custom domain cannot activate before ownership and HTTPS verification" do
    domain = @company.company_domains.create!(hostname: "app.#{SecureRandom.hex(3)}.example.com", kind: "custom",
      status: "pending", cname_target: "tenants.example.net")
    domain.status = "active"
    assert_not domain.valid?
    assert_includes domain.errors[:status], "requiere propiedad verificada"
    assert_includes domain.errors[:tls_status], "debe estar listo antes de activar"
  end

  test "verified custom domain can become primary without removing platform fallback" do
    domain = @company.company_domains.create!(hostname: "app.#{SecureRandom.hex(3)}.example.com", kind: "custom",
      status: "active", cname_target: "tenants.example.net", verified_at: Time.current, tls_status: "ready",
      activated_at: Time.current)
    @company.platform_domain.update!(primary: false)
    domain.update!(primary: true)

    assert_equal domain, @company.reload.primary_domain
    assert @company.platform_domain.active?
  end

  test "authentication codes expire" do
    user = create_user
    membership = create_membership(company: @company, user:, roles: %w[admin])
    request, = AuthenticationRequest.issue!(company: @company, company_domain: @company.platform_domain,
      return_hostname: @company.platform_domain.hostname, browser_nonce: "nonce")
    code, = AuthenticationCode.issue!(authentication_request: request, user:, membership:, expires_in: -1.second)

    assert_not code.available?
  end

  test "DNS ownership CNAME and HTTPS are all required before activation" do
    domain = @company.company_domains.create!(hostname: "app.#{SecureRandom.hex(3)}.example.com", kind: "custom",
      status: "pending", cname_target: "tenants.example.net")
    token = domain.issue_verification_token!
    txt = Resolv::DNS::Resource::IN::TXT.new("tenant-verification=#{token}")
    cname = Resolv::DNS::Resource::IN::CNAME.new(Resolv::DNS::Name.create("tenants.example.net"))
    resolver = Object.new
    resolver.define_singleton_method(:getresources) do |_name, type|
      type == Resolv::DNS::Resource::IN::TXT ? [ txt ] : [ cname ]
    end

    result = CompanyDomains::Verifier.call(domain, dns: resolver, https_probe: ->(_host) { true })

    assert result.ownership
    assert result.cname
    assert result.tls
    assert_equal :initial, result.mode
    assert_equal "verified", domain.reload.status
    assert_equal "ready", domain.tls_status
  end

  test "successful reverification preserves an active primary custom domain" do
    domain, resolver = active_custom_domain(primary: true)
    previous_verified_at = domain.verified_at

    result = CompanyDomains::Verifier.call(domain, dns: resolver, https_probe: ->(_host) { true })

    assert result.reverification?
    assert_empty result.errors
    assert_equal "active", domain.reload.status
    assert domain.primary?
    assert_equal "ready", domain.tls_status
    assert_operator domain.verified_at, :>, previous_verified_at
  end

  test "successful reverification preserves an active secondary custom domain" do
    domain, resolver = active_custom_domain

    result = CompanyDomains::Verifier.call(domain, dns: resolver, https_probe: ->(_host) { true })

    assert result.reverification?
    assert_equal "active", domain.reload.status
    assert_not domain.primary?
    assert @company.platform_domain.reload.primary?
  end

  test "DNS failure during reverification does not change operational state" do
    domain, = active_custom_domain(primary: true)
    operational_state = domain.attributes.slice("status", "primary", "tls_status", "verified_at", "activated_at")
    resolver = Object.new
    resolver.define_singleton_method(:getresources) { |_name, _type| [] }

    result = CompanyDomains::Verifier.call(domain, dns: resolver,
      https_probe: ->(_host) { flunk("HTTPS must not be probed when DNS verification failed") })

    assert result.reverification?
    assert_includes result.errors, "Falta el TXT de propiedad"
    assert_equal operational_state, domain.reload.attributes.slice(*operational_state.keys)
  end

  test "TLS failure during reverification does not change operational state" do
    domain, resolver = active_custom_domain
    operational_state = domain.attributes.slice("status", "primary", "tls_status", "verified_at", "activated_at")

    result = CompanyDomains::Verifier.call(domain, dns: resolver, https_probe: ->(_host) { false })

    assert result.reverification?
    assert_includes result.errors, "HTTPS todavía no presenta un certificado válido"
    assert_equal operational_state, domain.reload.attributes.slice(*operational_state.keys)
  end

  test "accepting the same invitation twice is idempotent" do
    user = create_user
    invitation, = CompanyInvitation.issue!(company: @company, email: user.email, roles: %w[admin])

    first = invitation.accept!(user)
    second = invitation.accept!(user)

    assert_equal first, second
    assert_equal 1, @company.memberships.where(user:).count
    assert_equal 1, first.membership_roles.where(role: "admin").count
  end

  private

  def active_custom_domain(primary: false)
    domain = @company.company_domains.create!(hostname: "app.#{SecureRandom.hex(3)}.example.com", kind: "custom",
      status: "pending", cname_target: "tenants.example.net")
    token = domain.issue_verification_token!
    domain.update!(status: "active", verified_at: 1.day.ago, tls_status: "ready", activated_at: 1.day.ago)
    CompanyDomains::MakePrimary.call(company: @company, company_domain: domain) if primary

    txt = Resolv::DNS::Resource::IN::TXT.new("tenant-verification=#{token}")
    cname = Resolv::DNS::Resource::IN::CNAME.new(Resolv::DNS::Name.create("tenants.example.net"))
    resolver = Object.new
    resolver.define_singleton_method(:getresources) do |_name, type|
      type == Resolv::DNS::Resource::IN::TXT ? [ txt ] : [ cname ]
    end
    [ domain.reload, resolver ]
  end
end
