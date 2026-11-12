class CreateAgentClients < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_clients, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :phone
      t.string :email
      t.datetime :archived_at
      t.timestamps
    end
    add_index :agent_clients, %i[id agent_workspace_id], unique: true
    add_index :agent_clients, %i[agent_workspace_id archived_at name]
    create_table :agent_client_notes, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
      t.references :agent_client, type: :uuid, null: false
      t.references :agent_trip, type: :uuid
      t.text :body, null: false
      t.timestamps
    end
    add_foreign_key :agent_client_notes, :agent_clients, column: %i[agent_client_id agent_workspace_id], primary_key: %i[id agent_workspace_id]
    add_foreign_key :agent_client_notes, :agent_trips, column: %i[agent_trip_id agent_workspace_id], primary_key: %i[id agent_workspace_id]
  end
end
