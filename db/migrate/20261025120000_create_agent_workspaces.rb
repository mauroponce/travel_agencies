class CreateAgentWorkspaces < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_workspaces, id: :uuid do |t|
      t.references :owner, type: :uuid, null: false, foreign_key: { to_table: :users }, index: { unique: true }
      t.string :business_name, null: false
      t.string :public_name, null: false
      t.string :whatsapp, null: false
      t.string :subdomain, null: false
      t.string :timezone, null: false, default: "America/Argentina/Buenos_Aires"
      t.string :status, null: false, default: "active"
      t.string :plan, null: false, default: "agent_pilot"
      t.text :presentation
      t.timestamps
    end
    add_index :agent_workspaces, :subdomain, unique: true
    add_check_constraint :agent_workspaces, "status IN ('active', 'suspended')", name: "agent_workspace_status"

    create_table :hostname_registrations, id: :uuid do |t|
      t.string :hostname, null: false
      t.references :company, type: :uuid, foreign_key: true
      t.references :agent_workspace, type: :uuid, foreign_key: true, index: { unique: true }
      t.timestamps
    end
    add_index :hostname_registrations, "lower(hostname)", unique: true, name: "uidx_registered_hostname"
    add_index :hostname_registrations, %i[hostname company_id], unique: true, name: "uidx_host_company"
    add_check_constraint :hostname_registrations, "(company_id IS NULL) <> (agent_workspace_id IS NULL)", name: "registered_host_owner"
    add_check_constraint :hostname_registrations, "hostname = lower(hostname) AND hostname !~ '\\.$'", name: "registered_host_normalized"
    reversible do |direction|
      direction.up do
        execute <<~SQL
          INSERT INTO hostname_registrations (id, hostname, company_id, created_at, updated_at)
          SELECT gen_random_uuid(), hostname, company_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM company_domains
        SQL
      end
    end

    create_table :agent_suppliers, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :contact_name
      t.string :phone
      t.string :email
      t.text :commercial_terms
      t.text :commission_terms
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :agent_suppliers, %i[id agent_workspace_id], unique: true
    add_index :agent_suppliers, %i[agent_workspace_id name]
    add_check_constraint :agent_suppliers, "status IN ('active', 'paused')", name: "agent_supplier_status"

    create_table :agent_trips, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.uuid :current_revision_id
      t.uuid :published_revision_id
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :agent_trips, %i[id agent_workspace_id], unique: true
    add_index :agent_trips, %i[agent_workspace_id slug], unique: true
    add_check_constraint :agent_trips, "status IN ('draft', 'published', 'unpublished', 'archived')", name: "agent_trip_status"
    add_check_constraint :agent_trips, "status <> 'published' OR published_revision_id IS NOT NULL", name: "agent_trip_published_revision"

    create_table :agent_trip_revisions, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
      t.references :agent_trip, type: :uuid, null: false, foreign_key: true
      t.references :agent_supplier, type: :uuid, null: false, foreign_key: true
      t.string :title
      t.string :destination
      t.string :region
      t.date :departs_on
      t.date :returns_on
      t.integer :duration_days
      t.bigint :price_cents
      t.string :currency
      t.string :price_unit
      t.string :price_basis
      t.string :hotel
      t.string :meal_plan
      t.string :transport
      t.string :departure_location
      t.text :included_services
      t.text :excluded_services
      t.text :conditions
      t.jsonb :warnings, null: false, default: []
      t.jsonb :evidence, null: false, default: {}
      t.timestamps
    end
    add_index :agent_trip_revisions, %i[id agent_workspace_id], unique: true
    add_index :agent_trip_revisions, %i[id agent_trip_id agent_workspace_id], unique: true, name: "uidx_agent_revision_trip_workspace"
    add_index :agent_trip_revisions, %i[agent_workspace_id departs_on]
    add_index :agent_trip_revisions, %i[agent_workspace_id currency price_unit price_cents], name: "idx_agent_revision_price"
    add_check_constraint :agent_trip_revisions, "price_cents IS NULL OR price_cents >= 0", name: "agent_price_nonnegative"
    add_check_constraint :agent_trip_revisions, "returns_on IS NULL OR departs_on IS NULL OR returns_on >= departs_on", name: "agent_trip_dates"
    add_foreign_key :agent_trip_revisions, :agent_trips, column: %i[agent_trip_id agent_workspace_id], primary_key: %i[id agent_workspace_id]
    add_foreign_key :agent_trip_revisions, :agent_suppliers, column: %i[agent_supplier_id agent_workspace_id], primary_key: %i[id agent_workspace_id]
    %i[current_revision_id published_revision_id].each do |column|
      add_foreign_key :agent_trips, :agent_trip_revisions, column: [ column, :id, :agent_workspace_id ], primary_key: %i[id agent_trip_id agent_workspace_id], name: "fk_agent_trip_#{column}"
    end

    %i[agent_imports agent_searches].each do |table|
      create_table table, id: :uuid do |t|
        t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
        t.string :idempotency_key, null: false
        t.string :status, null: false, default: "pending"
        t.string :processing_token
        t.datetime :started_at
        t.integer :attempts, null: false, default: 0
        t.string :error_code
        t.string :file_digest if table == :agent_imports
        t.text :query if table == :agent_searches
        t.jsonb :filters, null: false, default: {} if table == :agent_searches
        t.jsonb :interpretation, null: false, default: [] if table == :agent_searches
        t.timestamps
      end
      add_index table, %i[id agent_workspace_id], unique: true
      add_index table, %i[agent_workspace_id idempotency_key], unique: true, name: "uidx_#{table}_request"
      add_index table, %i[status started_at]
      add_check_constraint table, "status IN ('pending', 'processing', 'completed', 'error')", name: "#{table}_status"
    end

    create_table :agent_import_items, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
      t.references :agent_import, type: :uuid, null: false, foreign_key: true
      t.integer :position, null: false
      t.jsonb :extracted, null: false, default: {}
      t.references :agent_trip, type: :uuid, foreign_key: true
      t.references :agent_trip_revision, type: :uuid, foreign_key: true
      t.timestamps
    end
    add_index :agent_import_items, %i[agent_import_id position], unique: true
    add_foreign_key :agent_import_items, :agent_imports, column: %i[agent_import_id agent_workspace_id], primary_key: %i[id agent_workspace_id]
    add_foreign_key :agent_import_items, :agent_trips, column: %i[agent_trip_id agent_workspace_id], primary_key: %i[id agent_workspace_id]
    add_foreign_key :agent_import_items, :agent_trip_revisions, column: %i[agent_trip_revision_id agent_trip_id agent_workspace_id], primary_key: %i[id agent_trip_id agent_workspace_id], name: "fk_agent_import_item_revision"

    create_table :agent_ai_executions, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true
      t.references :agent_import, type: :uuid, foreign_key: true
      t.references :agent_search, type: :uuid, foreign_key: true
      t.string :model, null: false
      t.string :contract_version, null: false
      t.string :status, null: false
      t.string :error_code
      t.integer :duration_ms
      t.jsonb :usage, null: false, default: {}
      t.timestamps
    end
    add_check_constraint :agent_ai_executions, "(agent_import_id IS NULL) <> (agent_search_id IS NULL)", name: "agent_ai_execution_source"
    %i[agent_import agent_search].each do |source|
      add_foreign_key :agent_ai_executions, source.to_s.pluralize.to_sym, column: [ :"#{source}_id", :agent_workspace_id ], primary_key: %i[id agent_workspace_id]
    end

    %i[authentication_requests authentication_codes].each do |table|
      add_reference table, :agent_workspace, type: :uuid, foreign_key: true
      add_column table, :purpose, :string
      reversible do |direction|
        direction.up { execute "UPDATE #{table} SET purpose = CASE WHEN company_id IS NULL THEN 'operator' ELSE 'company' END" }
      end
      owner_column = table == :authentication_requests ? "company_domain_id" : "membership_id"
      add_check_constraint table, "(purpose IS NULL AND agent_workspace_id IS NULL) OR (purpose = 'company' AND company_id IS NOT NULL AND #{owner_column} IS NOT NULL AND agent_workspace_id IS NULL) OR (purpose = 'agent' AND company_id IS NULL AND #{owner_column} IS NULL AND agent_workspace_id IS NOT NULL) OR (purpose IN ('operator', 'agent_onboarding') AND company_id IS NULL AND #{owner_column} IS NULL AND agent_workspace_id IS NULL)", name: "#{table}_purpose"
      add_index table, %i[id agent_workspace_id], unique: true
    end
    add_foreign_key :authentication_codes, :authentication_requests, column: %i[authentication_request_id agent_workspace_id], primary_key: %i[id agent_workspace_id], name: "fk_auth_code_agent_request"
    add_reference :audit_events, :agent_workspace, type: :uuid, foreign_key: true
  end
end
