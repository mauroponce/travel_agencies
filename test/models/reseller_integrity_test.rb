require "test_helper"
require_relative "../support_agent_data"

class ResellerIntegrityTest < ActiveSupport::TestCase
  include AgentTestData

  test "supplier names are normalized and database rejects duplicates within workspace" do
    workspace = agent_workspace
    supplier = workspace.agent_suppliers.create!(name: "  Carlos Sansot   Viajes  ")
    assert_equal "Carlos Sansot Viajes", supplier.name
    assert_not workspace.agent_suppliers.new(name: "carlos sansot viajes").valid?
    assert agent_workspace.agent_suppliers.create!(name: supplier.name).persisted?
    assert_raises(ActiveRecord::RecordNotUnique) do
      AgentSupplier.transaction(requires_new: true) do
        AgentSupplier.insert_all!([ { agent_workspace_id: workspace.id, name: "CARLOS SANSOT VIAJES" } ])
      end
    end
  end

  test "Argentine amounts use dots for thousands and commas for cents" do
    { "450.000" => 45_000_000, "1.250.000,50" => 125_000_050, "450000.50" => 45_000_050, "450000,50" => 45_000_050 }.each do |input, cents|
      assert_equal cents, Agent::MoneyParser.call(input)
    end
    assert_raises(MoneyParser::InvalidAmount) { Agent::MoneyParser.call("precio a consultar") }
  end

  test "PDF share image renders first page only even when further pages change" do
    outputs = [ nil, "Segunda pagina" ].map do |second_page|
      document = Prawn::Document.new do
        text "Primera pagina"
        if second_page
          start_new_page
          text second_page
        end
      end
      file = Tempfile.new([ "reseller-first-page", ".pdf" ])
      begin
        file.binmode
        file.write(document.render)
        file.flush
        result = nil
        Agent::Flyer.render_pdf(file.path) { |image| result = image.read }
        result
      ensure
        file.close!
      end
    end
    assert_equal outputs.first, outputs.last
  end

  test "foreign sources and import items cannot be assigned by save service" do
    workspace = agent_workspace
    other = agent_workspace
    task = other.agent_imports.create!(idempotency_key: SecureRandom.uuid)
    item = task.items.create!(agent_workspace: other, position: 0)
    assert_raises(ActiveRecord::RecordNotFound) { Agent::SaveTrip.call(workspace:, attributes: {}, source_import: task) }
    assert_raises(ActiveRecord::RecordNotFound) { Agent::SaveTrip.call(workspace:, attributes: {}, item:) }
    assert_empty workspace.agent_trips
  end

  test "suspension prevents saving and publishing" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    trip.agent_workspace # Load the association before a separate suspension.
    workspace.update!(status: "suspended")
    assert_raises(Pundit::NotAuthorizedError) { Agent::SaveTrip.call(workspace:, attributes: {}, trip:) }
    assert_raises(ActiveRecord::RecordInvalid) { trip.publish! }
    assert_equal "draft", trip.reload.status
  end

  test "revision foreign keys and duplicate slugs are enforced in PostgreSQL" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    other = agent_trip(workspace: agent_workspace)
    assert_raises(ActiveRecord::InvalidForeignKey) do
      AgentTripRevision.transaction(requires_new: true) { trip.current_revision.update_columns(agent_supplier_id: other.current_revision.agent_supplier_id) }
    end
    assert_raises(ActiveRecord::RecordNotUnique) do
      AgentTrip.transaction(requires_new: true) { workspace.agent_trips.insert_all!([ { slug: trip.slug } ]) }
    end
  end
end
