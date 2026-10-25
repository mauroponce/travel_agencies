class StrengthenAgentReferenceIntegrity < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_check_constraint :agent_import_items, "(agent_trip_id IS NULL) = (agent_trip_revision_id IS NULL)",
      name: "agent_import_item_saved_revision", validate: false
    validate_check_constraint :agent_import_items, name: "agent_import_item_saved_revision"
    add_index :authentication_requests, %i[id purpose], unique: true, algorithm: :concurrently,
      name: "uidx_auth_request_purpose"
    add_foreign_key :authentication_codes, :authentication_requests,
      column: %i[authentication_request_id purpose], primary_key: %i[id purpose],
      name: "fk_auth_code_request_purpose", validate: false
    validate_foreign_key :authentication_codes, name: "fk_auth_code_request_purpose"
  end

  def down
    remove_foreign_key :authentication_codes, name: "fk_auth_code_request_purpose"
    remove_index :authentication_requests, name: "uidx_auth_request_purpose", algorithm: :concurrently
    remove_check_constraint :agent_import_items, name: "agent_import_item_saved_revision"
  end
end
