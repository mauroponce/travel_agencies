class CompleteResellerCatalog < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_suppliers, :website, :string
    add_column :agent_suppliers, :notes, :text
    add_index :agent_suppliers, "agent_workspace_id, lower(btrim(name))", unique: true, name: "uidx_agent_supplier_name"
    add_column :agent_trip_revisions, :description, :text
    add_column :agent_trip_revisions, :duration_nights, :integer
    add_check_constraint :agent_trip_revisions, "duration_nights IS NULL OR duration_nights >= 0", name: "agent_nights_nonnegative"
    add_check_constraint :agent_trip_revisions, "duration_days IS NULL OR duration_days > 0", name: "agent_days_positive"
    add_check_constraint :agent_trip_revisions, "currency IS NULL OR currency = '' OR currency IN ('ARS', 'USD', 'EUR', 'BRL')", name: "agent_currency"
    add_column :agent_workspaces, :invited_email, :string
    change_column_null :agent_workspaces, :owner_id, true
    add_check_constraint :agent_workspaces, "owner_id IS NOT NULL OR (invited_email IS NOT NULL AND invited_email <> '')", name: "agent_workspace_identity"
    add_index :agent_workspaces, "lower(invited_email)", unique: true, where: "invited_email IS NOT NULL", name: "uidx_agent_invited_email"
  end
end
