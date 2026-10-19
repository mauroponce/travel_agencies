class CreateNexoviajesDomain < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :users, id: :uuid do |t|
      t.string :google_sub, null: false
      t.string :email, null: false
      t.string :name, null: false
      t.string :avatar_url
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :users, :google_sub, unique: true
    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"

    create_table :platform_roles, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :role, null: false, default: "operator"
      t.timestamps
    end
    add_index :platform_roles, [ :user_id, :role ], unique: true

    create_table :companies, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :legal_name
      t.string :email
      t.string :whatsapp
      t.string :timezone, null: false, default: "America/Argentina/Buenos_Aires"
      t.string :status, null: false, default: "active"
      t.integer :balance_due_days_before, null: false, default: 5
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :companies, :slug, unique: true

    create_table :memberships, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :memberships, [ :company_id, :user_id ], unique: true

    create_table :membership_roles, id: :uuid do |t|
      t.references :membership, null: false, type: :uuid, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :membership_roles, [ :membership_id, :role ], unique: true

    create_table :reseller_authorizations, id: :uuid do |t|
      t.references :membership, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.boolean :auto_confirm_enabled, null: false, default: false
      t.string :public_code, null: false
      t.string :status, null: false, default: "active"
      t.timestamps
    end
    add_index :reseller_authorizations, :public_code, unique: true

    create_table :company_invitations, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :invited_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :email, null: false
      t.string :token_digest, null: false
      t.string :roles, array: true, null: false, default: []
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :company_invitations, :token_digest, unique: true
    add_index :company_invitations, [ :company_id, :email ]

    create_table :destinations, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.string :province
      t.text :description
      t.timestamps
    end
    add_index :destinations, [ :company_id, :name ], unique: true

    create_table :accommodations, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :destination, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.string :category
      t.string :address
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.string :google_place_id
      t.string :maps_url
      t.string :website_url
      t.text :services
      t.text :notes
      t.timestamps
    end
    add_index :accommodations, [ :company_id, :name ]

    create_table :buses, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.string :registration
      t.integer :capacity, null: false
      t.string :operator_name
      t.timestamps
    end

    create_table :boarding_points, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.string :address, null: false
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.text :notes
      t.timestamps
    end

    create_table :routes, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    create_table :route_stages, id: :uuid do |t|
      t.references :route, null: false, type: :uuid, foreign_key: true
      t.references :boarding_point, type: :uuid, foreign_key: true
      t.references :accommodation, type: :uuid, foreign_key: true
      t.integer :position, null: false
      t.string :kind, null: false, default: "boarding"
      t.text :instructions
      t.timestamps
    end
    add_index :route_stages, [ :route_id, :position ], unique: true

    create_table :travel_packages, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :destination, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :days, null: false
      t.integer :nights, null: false
      t.text :included_services, array: true, null: false, default: []
      t.text :excluded_services, array: true, null: false, default: []
      t.jsonb :faqs, null: false, default: []
      t.text :commercial_terms
      t.timestamps
    end

    create_table :departures, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :bus, null: false, type: :uuid, foreign_key: true
      t.references :route, type: :uuid, foreign_key: true
      t.string :code, null: false
      t.datetime :departs_at, null: false
      t.datetime :returns_at
      t.integer :capacity, null: false
      t.string :status, null: false, default: "open"
      t.text :return_notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :departures, [ :company_id, :code ], unique: true

    create_table :departure_stops, id: :uuid do |t|
      t.references :departure, null: false, type: :uuid, foreign_key: true
      t.references :boarding_point, null: false, type: :uuid, foreign_key: true
      t.integer :position, null: false
      t.datetime :scheduled_at, null: false
      t.string :published_name, null: false
      t.string :published_address, null: false
      t.text :instructions
      t.timestamps
    end
    add_index :departure_stops, [ :departure_id, :position ], unique: true

    create_table :departure_offers, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :travel_package, null: false, type: :uuid, foreign_key: true
      t.references :departure, null: false, type: :uuid, foreign_key: true
      t.references :accommodation, null: false, type: :uuid, foreign_key: true
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.timestamps
    end
    add_index :departure_offers, [ :company_id, :slug ], unique: true

    create_table :fare_versions, id: :uuid do |t|
      t.references :departure_offer, null: false, type: :uuid, foreign_key: true
      t.bigint :price_cents, null: false
      t.bigint :service_fee_cents, null: false, default: 0
      t.string :deposit_type, null: false, default: "fixed"
      t.bigint :deposit_cents, null: false, default: 0
      t.string :promotion_label
      t.datetime :valid_from, null: false
      t.datetime :valid_until
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :fare_versions, [ :departure_offer_id, :valid_from ]

    create_table :passenger_forms, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :departure_offer, null: false, type: :uuid, foreign_key: true
      t.references :reseller_membership, null: false, type: :uuid, foreign_key: { to_table: :memberships }
      t.string :token_digest, null: false
      t.string :prefilled_name
      t.datetime :expires_at, null: false
      t.datetime :submitted_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :passenger_forms, :token_digest, unique: true

    create_table :passenger_form_submissions, id: :uuid do |t|
      t.references :passenger_form, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.text :full_name, null: false
      t.text :document_number, null: false
      t.string :document_last4, null: false
      t.string :nationality, null: false
      t.references :departure_stop, null: false, type: :uuid, foreign_key: true
      t.string :room_type
      t.text :notes
      t.timestamps
    end

    create_table :reservations, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :departure_offer, null: false, type: :uuid, foreign_key: true
      t.references :seller_membership, type: :uuid, foreign_key: { to_table: :memberships }
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :code, null: false
      t.string :channel, null: false
      t.string :status, null: false, default: "requested"
      t.bigint :unit_price_cents
      t.bigint :unit_fee_cents
      t.bigint :minimum_payment_cents
      t.jsonb :terms_snapshot, null: false, default: {}
      t.string :idempotency_key
      t.datetime :confirmed_at
      t.datetime :cancelled_at
      t.text :cancellation_reason
      t.timestamps
    end
    add_index :reservations, [ :company_id, :code ], unique: true
    add_index :reservations, [ :company_id, :idempotency_key ], unique: true, where: "idempotency_key IS NOT NULL"

    create_table :passengers, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :reservation, null: false, type: :uuid, foreign_key: true
      t.references :departure_stop, null: false, type: :uuid, foreign_key: true
      t.references :accommodation, null: false, type: :uuid, foreign_key: true
      t.text :full_name, null: false
      t.text :document_number, null: false
      t.string :document_last4, null: false
      t.string :nationality, null: false
      t.string :room_type
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    create_table :seat_allocations, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :departure, null: false, type: :uuid, foreign_key: true
      t.references :passenger, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "active"
      t.datetime :released_at
      t.timestamps
    end
    add_index :seat_allocations, [ :departure_id, :status ]

    create_table :room_assignments, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :departure, null: false, type: :uuid, foreign_key: true
      t.references :accommodation, null: false, type: :uuid, foreign_key: true
      t.string :room_label
      t.string :room_type, null: false
      t.text :notes
      t.timestamps
    end

    create_table :room_assignment_passengers, id: :uuid do |t|
      t.references :room_assignment, null: false, type: :uuid, foreign_key: true
      t.references :passenger, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table :customer_payments, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :reservation, null: false, type: :uuid, foreign_key: true
      t.references :recorded_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :received_by_membership, type: :uuid, foreign_key: { to_table: :memberships }
      t.bigint :amount_cents, null: false
      t.string :method, null: false
      t.date :received_on, null: false
      t.string :status, null: false, default: "declared"
      t.text :notes
      t.timestamps
    end

    create_table :remittances, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :reseller_membership, null: false, type: :uuid, foreign_key: { to_table: :memberships }
      t.references :declared_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :verified_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :code, null: false
      t.bigint :amount_cents, null: false
      t.string :method, null: false
      t.string :status, null: false, default: "declared"
      t.date :declared_on, null: false
      t.datetime :verified_at
      t.text :notes
      t.timestamps
    end
    add_index :remittances, [ :company_id, :code ], unique: true

    create_table :remittance_allocations, id: :uuid do |t|
      t.references :remittance, null: false, type: :uuid, foreign_key: true
      t.references :customer_payment, null: false, type: :uuid, foreign_key: true
      t.bigint :amount_cents, null: false
      t.timestamps
    end
    add_index :remittance_allocations, [ :remittance_id, :customer_payment_id ], unique: true

    create_table :commission_rules, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :reseller_membership, null: false, type: :uuid, foreign_key: { to_table: :memberships }
      t.string :kind, null: false
      t.decimal :percentage, precision: 7, scale: 4
      t.bigint :fixed_cents
      t.string :status, null: false, default: "active"
      t.timestamps
    end

    create_table :commission_entries, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :reservation, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.references :reseller_membership, null: false, type: :uuid, foreign_key: { to_table: :memberships }
      t.bigint :amount_cents, null: false
      t.string :calculation_kind, null: false
      t.jsonb :rule_snapshot, null: false, default: {}
      t.string :status, null: false, default: "accrued"
      t.timestamps
    end

    create_table :departure_assignments, id: :uuid do |t|
      t.references :departure, null: false, type: :uuid, foreign_key: true
      t.references :membership, null: false, type: :uuid, foreign_key: true
      t.timestamps
    end
    add_index :departure_assignments, [ :departure_id, :membership_id ], unique: true

    create_table :boarding_events, id: :uuid do |t|
      t.references :company, null: false, type: :uuid, foreign_key: true
      t.references :departure, null: false, type: :uuid, foreign_key: true
      t.references :passenger, null: false, type: :uuid, foreign_key: true
      t.references :recorded_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.uuid :command_id, null: false
      t.string :status, null: false
      t.integer :base_version, null: false
      t.datetime :occurred_at, null: false
      t.text :notes
      t.timestamps
    end
    add_index :boarding_events, :command_id, unique: true
    add_index :boarding_events, [ :passenger_id, :created_at ]

    create_table :notifications, id: :uuid do |t|
      t.references :company, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :event_type, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :deduplication_key, null: false
      t.string :action_url
      t.jsonb :metadata, null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [ :user_id, :deduplication_key ], unique: true

    create_table :notification_preferences, id: :uuid do |t|
      t.references :membership, null: false, type: :uuid, foreign_key: true
      t.string :event_type, null: false
      t.boolean :in_app, null: false, default: true
      t.boolean :email, null: false, default: true
      t.boolean :web_push, null: false, default: true
      t.timestamps
    end
    add_index :notification_preferences, [ :membership_id, :event_type ], unique: true

    create_table :push_subscriptions, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.text :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :user_agent
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true

    create_table :audit_events, id: :uuid do |t|
      t.references :company, type: :uuid, foreign_key: true
      t.references :actor, type: :uuid, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :auditable_type, null: false
      t.uuid :auditable_id, null: false
      t.jsonb :changeset, null: false, default: {}
      t.string :request_id
      t.inet :ip_address
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :audit_events, [ :company_id, :occurred_at ]

    add_check_constraint :buses, "capacity > 0", name: "buses_capacity_positive"
    add_check_constraint :departures, "capacity > 0", name: "departures_capacity_positive"
    add_check_constraint :fare_versions, "price_cents >= 0 AND service_fee_cents >= 0 AND deposit_cents >= 0", name: "fare_amounts_nonnegative"
    add_check_constraint :customer_payments, "amount_cents > 0", name: "payments_amount_positive"
    add_check_constraint :remittances, "amount_cents > 0", name: "remittances_amount_positive"
    add_check_constraint :remittance_allocations, "amount_cents > 0", name: "remittance_allocations_positive"
    add_check_constraint :commission_entries, "amount_cents >= 0", name: "commission_entries_nonnegative"
  end
end
