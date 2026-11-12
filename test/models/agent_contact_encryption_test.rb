require "test_helper"
require_relative "../support_agent_data"
require Rails.root.join("db/migrate/20261112124000_encrypt_agent_contacts")

class AgentContactEncryptionTest < ActiveSupport::TestCase
  include AgentTestData

  test "contacts and notes use randomized ciphertext and exports retain formula protection" do
    workspace = agent_workspace
    first = workspace.agent_clients.create!(name: "=Persona privada", phone: "5491155551111", email: "private@example.test")
    second = workspace.agent_clients.create!(name: first.name, phone: first.phone, email: first.email)
    note = first.notes.create!(agent_workspace: workspace, body: "\t=NOTA PRIVADA")
    %w[name phone email].each do |field|
      assert first.reload.encrypted_attribute?(field)
      assert_not_equal first.read_attribute_before_type_cast(field), second.reload.read_attribute_before_type_cast(field)
      assert_not_includes first.read_attribute_before_type_cast(field), first.public_send(field)
    end
    assert note.reload.encrypted_attribute?(:body)
    assert_includes Agent::ContactExport.call(workspace:), "'=Persona privada"
    assert_includes Agent::ContactExport.call(workspace:, notes: true), "'\t=NOTA PRIVADA"
    assert_empty Agent::IntegrityAudit.call
  end

  test "substring search sorts decrypted names and keeps literal characters scope and archives" do
    workspace = agent_workspace
    first = workspace.agent_clients.create!(name: "Zeta 100%_real", phone: "5491155551111", email: "first@example.test")
    second = workspace.agent_clients.create!(name: "ana", phone: "5491155552222", email: "second@example.test")
    workspace.agent_clients.create!(name: "Archivo", phone: "5491155553333", archived_at: Time.current)
    agent_workspace.agent_clients.create!(name: "Otro 100%_real", phone: first.phone)
    scope = workspace.agent_clients.active
    assert_equal [ second.id, first.id ], Agent::ClientDirectory.call(scope:).pluck(:id)
    assert_equal [ second.id, first.id ], Agent::ClientDirectory.call(scope:, query: " \t ").pluck(:id)
    { "%_r" => first.id, "ZETA" => first.id, "51111" => first.id, "COND@EX" => second.id }.each do |query, id|
      assert_equal [ id ], Agent::ClientDirectory.call(scope:, query:).pluck(:id)
    end
    assert_empty Agent::ClientDirectory.call(scope:, query: "Archivo")
  end

  test "incremental migration preserves expired contacts references timestamps and historical terms and is resumable" do
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    client = workspace.agent_clients.create!(name: "Legacy Persona", phone: "5491155554444")
    note = client.notes.create!(agent_workspace: workspace, agent_trip: trip, body: "Legacy secret note")
    workspace.agent_subscription.update!(price_cents: 1500, trial_starts_at: 30.days.ago, trial_ends_at: 16.days.ago)
    workspace.update!(status: "suspended")
    timestamps = [ client.updated_at, note.updated_at ]
    write_raw(client, name: "Legacy Persona", phone: "5491155554444", email: nil)
    write_raw(note, body: "Legacy secret note")
    assert Agent::IntegrityAudit.call.any? { |message| message.include?("plaintext") }
    buffer = StringIO.new
    previous = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(buffer)
    migrate_contacts
    ciphertext = client.reload.read_attribute_before_type_cast(:name)
    migrate_contacts
    assert_equal ciphertext, client.reload.read_attribute_before_type_cast(:name)
    assert_equal "Legacy Persona", client.name
    assert_nil client.email
    assert_equal "Legacy secret note", note.reload.body
    assert_equal trip.id, note.agent_trip_id
    assert_equal timestamps, [ client.updated_at, note.updated_at ]
    assert_equal 1500, workspace.agent_subscription.reload.price_cents
    assert_not workspace.agent_subscription.entitled?
    assert_empty Agent::IntegrityAudit.call
    [ client.name, client.phone, note.body ].each { |secret| assert_not_includes buffer.string, secret }
  ensure
    ActiveRecord::Base.logger = previous if previous
  end

  test "migration fails without overwriting ciphertext encrypted under another key" do
    client = agent_workspace.agent_clients.create!(name: "Protected", phone: "5491155555555")
    other_key = ActiveRecord::Encryption::KeyProvider.new(ActiveRecord::Encryption::Key.new(SecureRandom.random_bytes(32)))
    ciphertext = ActiveRecord::Encryption.encryptor.encrypt("Never overwrite", key_provider: other_key)
    write_raw(client, name: ciphertext, phone: "5491155555555")
    assert_raises(ActiveRecord::Encryption::Errors::Decryption) { migrate_contacts }
    assert_equal ciphertext, client.reload.read_attribute_before_type_cast(:name)
    assert_raises(ActiveRecord::Encryption::Errors::Decryption) { client.name }
  end

  private

  def write_raw(record, attributes)
    connection = ApplicationRecord.connection
    assignments = attributes.map { |field, value| "#{connection.quote_column_name(field)} = #{connection.quote(value)}" }.join(", ")
    connection.execute("UPDATE #{record.class.table_name} SET #{assignments} WHERE id = #{connection.quote(record.id)}")
  end

  def migrate_contacts
    migration = EncryptAgentContacts.new
    migration.send(:encrypt_records, EncryptAgentContacts::Client, %w[name phone email])
    migration.send(:encrypt_records, EncryptAgentContacts::Note, %w[body])
  end
end
