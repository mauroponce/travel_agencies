require "test_helper"
require_relative "../support_agent_data"

class AgentSlugTest < ActiveSupport::TestCase
  include AgentTestData

  test "name fills both identities and a new workspace needs no subdomain" do
    workspace = AgentWorkspace.create!(owner: create_user, name: "  José Pérez Viajes  ", whatsapp: "5491155550101")
    assert_equal "José Pérez Viajes", workspace.business_name
    assert_equal workspace.business_name, workspace.public_name
    assert_equal "jose-perez-viajes", workspace.slug
    assert_nil workspace.subdomain
    assert_nil workspace.hostname_registration
    assert_equal PlatformHosts.url(host: PlatformHosts.platform_host, path: "/jose-perez-viajes"), workspace.url
    assert_empty Agent::IntegrityAudit.call
  end

  test "suggestions transliterate names collapse spaces and skip occupied and reserved slugs" do
    agent_workspace(slug: "jose-perez")
    agent_workspace(slug: "jose-perez-2", status: "suspended")
    assert_equal "jose-perez-3", AgentWorkspace.suggest_slug("  José   Pérez  ")
    assert_equal "viajes-2", AgentWorkspace.suggest_slug("Viajes")
    assert_equal "asesor-2", AgentWorkspace.suggest_slug("Asesor")
    assert_not AgentWorkspace.slug_available?("asesor")
    %w[autenticacion sesion alta contexto panel plataforma suscripciones-notificaciones].each do |slug|
      assert_not AgentWorkspace.slug_available?(slug), slug
    end
    assert AgentWorkspace.slug_available?(AgentWorkspace.suggest_slug("🌍"))
    long_name = "a" * 90
    agent_workspace(slug: "a" * 63)
    candidate = AgentWorkspace.suggest_slug(long_name)
    assert_equal "#{'a' * 61}-2", candidate
    assert_equal 63, candidate.length
  end

  test "slug uniqueness is enforced by the database and slugs are permanent" do
    first = agent_workspace(slug: "unico")
    second = agent_workspace
    assert_not second.update(slug: first.slug)
    assert_raises(ActiveRecord::RecordNotUnique) do
      AgentWorkspace.transaction(requires_new: true) { second.update_columns(slug: first.slug) }
    end
    assert_not first.update(slug: "otra-direccion")
    assert_not AgentWorkspace.slug_available?("../agente")
    assert_not AgentWorkspace.slug_available?("agente")
  end
end
