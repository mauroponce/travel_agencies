require "test_helper"
require_relative "../support_agent_data"

class AgentDomainTest < ActiveSupport::TestCase
  include AgentTestData

  test "workspace owner and subdomain are unique and permanent" do
    workspace = agent_workspace
    assert_equal workspace, TenantResolver.call(workspace.hostname).agent_workspace
    assert_equal :agent, TenantResolver.call(workspace.hostname).scope
    assert_not workspace.update(subdomain: "otro-subdominio")
    assert_not AgentWorkspace.new(workspace.attributes.except("id", "created_at", "updated_at")).valid?
    assert_not agent_workspace_record("auth").valid?
  end

  test "agent and company compete for the same registered hostname" do
    workspace = agent_workspace
    assert_raises(ActiveRecord::RecordNotUnique) do
      Company.create!(name: "Colisión", slug: workspace.subdomain)
    end
    company = Company.create!(name: "Empresa", slug: "empresa-#{SecureRandom.hex(4)}")
    assert_not agent_workspace_record(company.slug).valid?
    assert_empty Agent::IntegrityAudit.call
  end

  test "database rejects mixed host ownership and cross-workspace supplier" do
    first = agent_workspace
    second = agent_workspace
    trip = agent_trip(workspace: first)
    supplier = second.agent_suppliers.create!(name: "Ajeno")
    assert_raises(ActiveRecord::InvalidForeignKey) do
      AgentTripRevision.transaction(requires_new: true) { trip.current_revision.update_columns(agent_supplier_id: supplier.id) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      HostnameRegistration.transaction(requires_new: true) do
        first.hostname_registration.update_columns(company_id: Company.create!(name: "Test", slug: "test-#{SecureRandom.hex(3)}").id)
      end
    end
  end

  test "suspension blocks host resolution and publication" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    workspace.update!(status: "suspended")
    assert_raises(TenantResolver::UnknownHost) { TenantResolver.call(workspace.hostname) }
    assert_raises(ActiveRecord::RecordInvalid) { trip.publish! }
  end

  test "published revision stays stable until explicit republication" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    trip.publish!
    original = trip.published_revision
    Agent::SaveTrip.call(workspace:, trip:, expected_revision_id: trip.current_revision_id,
      attributes: original.attributes.slice(*AgentTripRevision::FIELDS).merge("price_cents" => 60_000_000))
    assert_equal 50_000_000, trip.reload.published_revision.price_cents
    assert_equal 60_000_000, trip.current_revision.price_cents
    trip.publish!
    assert_equal 60_000_000, trip.reload.published_revision.price_cents
    assert_equal 50_000_000, original.reload.price_cents
    assert_not original.update(title: "Sobrescritura")
  end

  test "draft accepts missing fields but publication requires reviewed commercial data" do
    workspace = agent_workspace
    supplier = workspace.agent_suppliers.create!(name: "Proveedor")
    trip = Agent::SaveTrip.call(workspace:, attributes: { "agent_supplier_id" => supplier.id })
    assert_equal "draft", trip.status
    assert_raises(ActiveRecord::RecordInvalid) { trip.publish! }
    assert_equal "draft", trip.reload.status
  end

  test "paused suppliers and expired departures are excluded without deleting publications" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    trip.publish!
    supplier = trip.current_revision.agent_supplier
    assert_includes workspace.agent_trips.publicly_visible, trip
    supplier.update!(status: "paused")
    assert_empty workspace.agent_trips.publicly_visible
    supplier.update!(status: "active")
    assert_includes workspace.agent_trips.publicly_visible, trip
    travel_to(4.months.from_now) { assert_empty workspace.agent_trips.publicly_visible }
  end

  test "catalog filters price only with compatible currency and unit" do
    workspace = agent_workspace
    cheap = agent_trip(workspace:)
    agent_trip(workspace:, price_cents: 900_000_00)
    agent_trip(workspace:, currency: "USD", price_cents: 100_00)
    agent_trip(workspace:, price_unit: "per_group", price_cents: 100_00)
    assert_equal [ cheap.id ], Agent::CatalogQuery.call(workspace:, filters: { max_price: "600000", currency: "ARS", price_unit: "per_person" }).pluck(:id)
    assert_empty Agent::CatalogQuery.call(workspace:, filters: { max_price: "600000" })
    assert_empty Agent::CatalogQuery.call(workspace:, filters: { from: "invalid" })
    assert_includes Agent::CatalogQuery.call(workspace:, filters: { destination: "cordoba" }).pluck(:id), cheap.id
  end

  test "stale edits cannot replace a newer draft" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    assert_raises(ActiveRecord::StaleObjectError) do
      Agent::SaveTrip.call(workspace:, trip:, attributes: trip.current_revision.attributes.slice(*AgentTripRevision::FIELDS), expected_revision_id: "stale")
    end
    assert_equal 1, trip.revisions.count
  end

  test "base domain migration moves company and agent registrations together" do
    old_value = ENV["PLATFORM_BASE_DOMAIN"]
    source = PlatformHosts.base_domain
    workspace = agent_workspace
    company = Company.create!(name: "Migración", slug: "base-#{SecureRandom.hex(3)}")
    target = "new-#{SecureRandom.hex(3)}.test"
    ENV["PLATFORM_BASE_DOMAIN"] = target
    plan = CompanyDomains::BaseDomainMigration.apply!(from: source, to: target)
    assert plan.safe?
    assert_equal "#{workspace.subdomain}.#{target}", workspace.hostname_registration.reload.hostname
    assert_equal "#{company.slug}.#{target}", company.platform_domain.reload.hostname
  ensure
    old_value ? ENV["PLATFORM_BASE_DOMAIN"] = old_value : ENV.delete("PLATFORM_BASE_DOMAIN")
  end

  private
  def agent_workspace_record(subdomain)
    AgentWorkspace.new(owner: create_user, business_name: "Test", public_name: "Test", whatsapp: "5491155550101", subdomain:)
  end
end
