class EncryptAgentContacts < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Frozen migration readers bypass commercial callbacks, including expired or
  # suspended workspaces. Plaintext support is confined to this transition.
  class Client < ActiveRecord::Base
    self.table_name = "agent_clients"
    encrypts :name, :phone, :email, support_unencrypted_data: true
  end

  class Note < ActiveRecord::Base
    self.table_name = "agent_client_notes"
    encrypts :body, support_unencrypted_data: true
  end

  def up
    encrypt_records(Client, %w[name phone email])
    encrypt_records(Note, %w[body])
    remove_index :agent_clients, %i[agent_workspace_id archived_at name], if_exists: true
    add_index :agent_clients, %i[agent_workspace_id archived_at id], if_not_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Keep the existing encryption key and encrypted readers; restore a verified backup or roll forward."
  end

  private

  def encrypt_records(model, fields)
    model.reset_column_information
    model.find_each(batch_size: 100) do |record|
      record.with_lock do
        plaintext = false
        fields.each do |field|
          raw = record.read_attribute_before_type_cast(field)
          next if raw.nil?
          if record.encrypted_attribute?(field)
            # The compatibility reader falls back on decryption failure. Verify
            # envelopes explicitly so a wrong key never overwrites ciphertext.
            ActiveRecord::Encryption.encryptor.decrypt(raw)
          else
            plaintext = true
          end
        end
        record.encrypt if plaintext
      end
    end
  end
end
