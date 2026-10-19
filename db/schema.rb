# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_19_170000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "accommodations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "destination_id", null: false
    t.string "name", null: false
    t.string "category"
    t.string "address"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "google_place_id"
    t.string "maps_url"
    t.string "website_url"
    t.text "services"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_accommodations_on_company_id_and_name"
    t.index ["company_id"], name: "index_accommodations_on_company_id"
    t.index ["destination_id"], name: "index_accommodations_on_destination_id"
  end

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audit_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id"
    t.uuid "actor_id"
    t.string "action", null: false
    t.string "auditable_type", null: false
    t.uuid "auditable_id", null: false
    t.jsonb "changeset", default: {}, null: false
    t.string "request_id"
    t.inet "ip_address"
    t.datetime "occurred_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_audit_events_on_actor_id"
    t.index ["company_id", "occurred_at"], name: "index_audit_events_on_company_id_and_occurred_at"
    t.index ["company_id"], name: "index_audit_events_on_company_id"
  end

  create_table "boarding_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "departure_id", null: false
    t.uuid "passenger_id", null: false
    t.uuid "recorded_by_id", null: false
    t.uuid "command_id", null: false
    t.string "status", null: false
    t.integer "base_version", null: false
    t.datetime "occurred_at", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["command_id"], name: "index_boarding_events_on_command_id", unique: true
    t.index ["company_id"], name: "index_boarding_events_on_company_id"
    t.index ["departure_id"], name: "index_boarding_events_on_departure_id"
    t.index ["passenger_id", "created_at"], name: "index_boarding_events_on_passenger_id_and_created_at"
    t.index ["passenger_id"], name: "index_boarding_events_on_passenger_id"
    t.index ["recorded_by_id"], name: "index_boarding_events_on_recorded_by_id"
  end

  create_table "boarding_points", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "address", null: false
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_boarding_points_on_company_id"
  end

  create_table "buses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "registration"
    t.integer "capacity", null: false
    t.string "operator_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_buses_on_company_id"
    t.check_constraint "capacity > 0", name: "buses_capacity_positive"
  end

  create_table "commission_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "reservation_id", null: false
    t.uuid "reseller_membership_id", null: false
    t.bigint "amount_cents", null: false
    t.string "calculation_kind", null: false
    t.jsonb "rule_snapshot", default: {}, null: false
    t.string "status", default: "accrued", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_commission_entries_on_company_id"
    t.index ["reseller_membership_id"], name: "index_commission_entries_on_reseller_membership_id"
    t.index ["reservation_id"], name: "index_commission_entries_on_reservation_id", unique: true
    t.check_constraint "amount_cents >= 0", name: "commission_entries_nonnegative"
  end

  create_table "commission_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "reseller_membership_id", null: false
    t.string "kind", null: false
    t.decimal "percentage", precision: 7, scale: 4
    t.bigint "fixed_cents"
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_commission_rules_on_company_id"
    t.index ["reseller_membership_id"], name: "index_commission_rules_on_reseller_membership_id"
  end

  create_table "companies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "legal_name"
    t.string "email"
    t.string "whatsapp"
    t.string "timezone", default: "America/Argentina/Buenos_Aires", null: false
    t.string "status", default: "active", null: false
    t.integer "balance_due_days_before", default: 5, null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_companies_on_slug", unique: true
  end

  create_table "company_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "invited_by_id"
    t.string "email", null: false
    t.string "token_digest", null: false
    t.string "roles", default: [], null: false, array: true
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "email"], name: "index_company_invitations_on_company_id_and_email"
    t.index ["company_id"], name: "index_company_invitations_on_company_id"
    t.index ["invited_by_id"], name: "index_company_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_company_invitations_on_token_digest", unique: true
  end

  create_table "customer_payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "reservation_id", null: false
    t.uuid "recorded_by_id", null: false
    t.uuid "received_by_membership_id"
    t.bigint "amount_cents", null: false
    t.string "method", null: false
    t.date "received_on", null: false
    t.string "status", default: "declared", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_customer_payments_on_company_id"
    t.index ["received_by_membership_id"], name: "index_customer_payments_on_received_by_membership_id"
    t.index ["recorded_by_id"], name: "index_customer_payments_on_recorded_by_id"
    t.index ["reservation_id"], name: "index_customer_payments_on_reservation_id"
    t.check_constraint "amount_cents > 0", name: "payments_amount_positive"
  end

  create_table "departure_assignments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "departure_id", null: false
    t.uuid "membership_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["departure_id", "membership_id"], name: "index_departure_assignments_on_departure_id_and_membership_id", unique: true
    t.index ["departure_id"], name: "index_departure_assignments_on_departure_id"
    t.index ["membership_id"], name: "index_departure_assignments_on_membership_id"
  end

  create_table "departure_offers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "travel_package_id", null: false
    t.uuid "departure_id", null: false
    t.uuid "accommodation_id", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accommodation_id"], name: "index_departure_offers_on_accommodation_id"
    t.index ["company_id", "slug"], name: "index_departure_offers_on_company_id_and_slug", unique: true
    t.index ["company_id"], name: "index_departure_offers_on_company_id"
    t.index ["departure_id"], name: "index_departure_offers_on_departure_id"
    t.index ["travel_package_id"], name: "index_departure_offers_on_travel_package_id"
  end

  create_table "departure_stops", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "departure_id", null: false
    t.uuid "boarding_point_id", null: false
    t.integer "position", null: false
    t.datetime "scheduled_at", null: false
    t.string "published_name", null: false
    t.string "published_address", null: false
    t.text "instructions"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["boarding_point_id"], name: "index_departure_stops_on_boarding_point_id"
    t.index ["departure_id", "position"], name: "index_departure_stops_on_departure_id_and_position", unique: true
    t.index ["departure_id"], name: "index_departure_stops_on_departure_id"
  end

  create_table "departures", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "bus_id", null: false
    t.uuid "route_id"
    t.string "code", null: false
    t.datetime "departs_at", null: false
    t.datetime "returns_at"
    t.integer "capacity", null: false
    t.string "status", default: "open", null: false
    t.text "return_notes"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id"], name: "index_departures_on_bus_id"
    t.index ["company_id", "code"], name: "index_departures_on_company_id_and_code", unique: true
    t.index ["company_id"], name: "index_departures_on_company_id"
    t.index ["route_id"], name: "index_departures_on_route_id"
    t.check_constraint "capacity > 0", name: "departures_capacity_positive"
  end

  create_table "destinations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.string "province"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "name"], name: "index_destinations_on_company_id_and_name", unique: true
    t.index ["company_id"], name: "index_destinations_on_company_id"
  end

  create_table "fare_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "departure_offer_id", null: false
    t.bigint "price_cents", null: false
    t.bigint "service_fee_cents", default: 0, null: false
    t.string "deposit_type", default: "fixed", null: false
    t.bigint "deposit_cents", default: 0, null: false
    t.string "promotion_label"
    t.datetime "valid_from", null: false
    t.datetime "valid_until"
    t.uuid "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_fare_versions_on_created_by_id"
    t.index ["departure_offer_id", "valid_from"], name: "index_fare_versions_on_departure_offer_id_and_valid_from"
    t.index ["departure_offer_id"], name: "index_fare_versions_on_departure_offer_id"
    t.check_constraint "price_cents >= 0 AND service_fee_cents >= 0 AND deposit_cents >= 0", name: "fare_amounts_nonnegative"
  end

  create_table "membership_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "membership_id", null: false
    t.string "role", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id", "role"], name: "index_membership_roles_on_membership_id_and_role", unique: true
    t.index ["membership_id"], name: "index_membership_roles_on_membership_id"
  end

  create_table "memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "user_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "user_id"], name: "index_memberships_on_company_id_and_user_id", unique: true
    t.index ["company_id"], name: "index_memberships_on_company_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "notification_preferences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "membership_id", null: false
    t.string "event_type", null: false
    t.boolean "in_app", default: true, null: false
    t.boolean "email", default: true, null: false
    t.boolean "web_push", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id", "event_type"], name: "index_notification_preferences_on_membership_id_and_event_type", unique: true
    t.index ["membership_id"], name: "index_notification_preferences_on_membership_id"
  end

  create_table "notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id"
    t.uuid "user_id", null: false
    t.string "event_type", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "deduplication_key", null: false
    t.string "action_url"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_notifications_on_company_id"
    t.index ["user_id", "deduplication_key"], name: "index_notifications_on_user_id_and_deduplication_key", unique: true
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "passenger_form_submissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "passenger_form_id", null: false
    t.text "full_name", null: false
    t.text "document_number", null: false
    t.string "document_last4", null: false
    t.string "nationality", null: false
    t.uuid "departure_stop_id", null: false
    t.string "room_type"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["departure_stop_id"], name: "index_passenger_form_submissions_on_departure_stop_id"
    t.index ["passenger_form_id"], name: "index_passenger_form_submissions_on_passenger_form_id", unique: true
  end

  create_table "passenger_forms", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "departure_offer_id", null: false
    t.uuid "reseller_membership_id", null: false
    t.string "token_digest", null: false
    t.string "prefilled_name"
    t.datetime "expires_at", null: false
    t.datetime "submitted_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_passenger_forms_on_company_id"
    t.index ["departure_offer_id"], name: "index_passenger_forms_on_departure_offer_id"
    t.index ["reseller_membership_id"], name: "index_passenger_forms_on_reseller_membership_id"
    t.index ["token_digest"], name: "index_passenger_forms_on_token_digest", unique: true
  end

  create_table "passengers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "reservation_id", null: false
    t.uuid "departure_stop_id", null: false
    t.uuid "accommodation_id", null: false
    t.text "full_name", null: false
    t.text "document_number", null: false
    t.string "document_last4", null: false
    t.string "nationality", null: false
    t.string "room_type"
    t.text "notes"
    t.integer "lock_version", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accommodation_id"], name: "index_passengers_on_accommodation_id"
    t.index ["company_id"], name: "index_passengers_on_company_id"
    t.index ["departure_stop_id"], name: "index_passengers_on_departure_stop_id"
    t.index ["reservation_id"], name: "index_passengers_on_reservation_id"
  end

  create_table "platform_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "role", default: "operator", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "role"], name: "index_platform_roles_on_user_id_and_role", unique: true
    t.index ["user_id"], name: "index_platform_roles_on_user_id"
  end

  create_table "push_subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.text "endpoint", null: false
    t.string "p256dh", null: false
    t.string "auth", null: false
    t.string "user_agent"
    t.datetime "last_used_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "remittance_allocations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "remittance_id", null: false
    t.uuid "customer_payment_id", null: false
    t.bigint "amount_cents", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_payment_id"], name: "index_remittance_allocations_on_customer_payment_id"
    t.index ["remittance_id", "customer_payment_id"], name: "idx_on_remittance_id_customer_payment_id_6b1a238f11", unique: true
    t.index ["remittance_id"], name: "index_remittance_allocations_on_remittance_id"
    t.check_constraint "amount_cents > 0", name: "remittance_allocations_positive"
  end

  create_table "remittances", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "reseller_membership_id", null: false
    t.uuid "declared_by_id", null: false
    t.uuid "verified_by_id"
    t.string "code", null: false
    t.bigint "amount_cents", null: false
    t.string "method", null: false
    t.string "status", default: "declared", null: false
    t.date "declared_on", null: false
    t.datetime "verified_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "code"], name: "index_remittances_on_company_id_and_code", unique: true
    t.index ["company_id"], name: "index_remittances_on_company_id"
    t.index ["declared_by_id"], name: "index_remittances_on_declared_by_id"
    t.index ["reseller_membership_id"], name: "index_remittances_on_reseller_membership_id"
    t.index ["verified_by_id"], name: "index_remittances_on_verified_by_id"
    t.check_constraint "amount_cents > 0", name: "remittances_amount_positive"
  end

  create_table "reseller_authorizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "membership_id", null: false
    t.boolean "auto_confirm_enabled", default: false, null: false
    t.string "public_code", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id"], name: "index_reseller_authorizations_on_membership_id", unique: true
    t.index ["public_code"], name: "index_reseller_authorizations_on_public_code", unique: true
  end

  create_table "reservations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "departure_offer_id", null: false
    t.uuid "seller_membership_id"
    t.uuid "created_by_id", null: false
    t.string "code", null: false
    t.string "channel", null: false
    t.string "status", default: "requested", null: false
    t.bigint "unit_price_cents"
    t.bigint "unit_fee_cents"
    t.bigint "minimum_payment_cents"
    t.jsonb "terms_snapshot", default: {}, null: false
    t.string "idempotency_key"
    t.datetime "confirmed_at"
    t.datetime "cancelled_at"
    t.text "cancellation_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "code"], name: "index_reservations_on_company_id_and_code", unique: true
    t.index ["company_id", "idempotency_key"], name: "index_reservations_on_company_id_and_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["company_id"], name: "index_reservations_on_company_id"
    t.index ["created_by_id"], name: "index_reservations_on_created_by_id"
    t.index ["departure_offer_id"], name: "index_reservations_on_departure_offer_id"
    t.index ["seller_membership_id"], name: "index_reservations_on_seller_membership_id"
  end

  create_table "room_assignment_passengers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "room_assignment_id", null: false
    t.uuid "passenger_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["passenger_id"], name: "index_room_assignment_passengers_on_passenger_id", unique: true
    t.index ["room_assignment_id"], name: "index_room_assignment_passengers_on_room_assignment_id"
  end

  create_table "room_assignments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "departure_id", null: false
    t.uuid "accommodation_id", null: false
    t.string "room_label"
    t.string "room_type", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accommodation_id"], name: "index_room_assignments_on_accommodation_id"
    t.index ["company_id"], name: "index_room_assignments_on_company_id"
    t.index ["departure_id"], name: "index_room_assignments_on_departure_id"
  end

  create_table "route_stages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "route_id", null: false
    t.uuid "boarding_point_id"
    t.uuid "accommodation_id"
    t.integer "position", null: false
    t.string "kind", default: "boarding", null: false
    t.text "instructions"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accommodation_id"], name: "index_route_stages_on_accommodation_id"
    t.index ["boarding_point_id"], name: "index_route_stages_on_boarding_point_id"
    t.index ["route_id", "position"], name: "index_route_stages_on_route_id_and_position", unique: true
    t.index ["route_id"], name: "index_route_stages_on_route_id"
  end

  create_table "routes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_routes_on_company_id"
  end

  create_table "seat_allocations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "departure_id", null: false
    t.uuid "passenger_id", null: false
    t.string "status", default: "active", null: false
    t.datetime "released_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_seat_allocations_on_company_id"
    t.index ["departure_id", "status"], name: "index_seat_allocations_on_departure_id_and_status"
    t.index ["departure_id"], name: "index_seat_allocations_on_departure_id"
    t.index ["passenger_id"], name: "index_seat_allocations_on_passenger_id", unique: true
  end

  create_table "travel_packages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "company_id", null: false
    t.uuid "destination_id", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "days", null: false
    t.integer "nights", null: false
    t.text "included_services", default: [], null: false, array: true
    t.text "excluded_services", default: [], null: false, array: true
    t.jsonb "faqs", default: [], null: false
    t.text "commercial_terms"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_travel_packages_on_company_id"
    t.index ["destination_id"], name: "index_travel_packages_on_destination_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "google_sub", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "avatar_url"
    t.datetime "last_login_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "phone"
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["google_sub"], name: "index_users_on_google_sub", unique: true
  end

  add_foreign_key "accommodations", "companies"
  add_foreign_key "accommodations", "destinations"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_events", "companies"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "boarding_events", "companies"
  add_foreign_key "boarding_events", "departures"
  add_foreign_key "boarding_events", "passengers"
  add_foreign_key "boarding_events", "users", column: "recorded_by_id"
  add_foreign_key "boarding_points", "companies"
  add_foreign_key "buses", "companies"
  add_foreign_key "commission_entries", "companies"
  add_foreign_key "commission_entries", "memberships", column: "reseller_membership_id"
  add_foreign_key "commission_entries", "reservations"
  add_foreign_key "commission_rules", "companies"
  add_foreign_key "commission_rules", "memberships", column: "reseller_membership_id"
  add_foreign_key "company_invitations", "companies"
  add_foreign_key "company_invitations", "users", column: "invited_by_id"
  add_foreign_key "customer_payments", "companies"
  add_foreign_key "customer_payments", "memberships", column: "received_by_membership_id"
  add_foreign_key "customer_payments", "reservations"
  add_foreign_key "customer_payments", "users", column: "recorded_by_id"
  add_foreign_key "departure_assignments", "departures"
  add_foreign_key "departure_assignments", "memberships"
  add_foreign_key "departure_offers", "accommodations"
  add_foreign_key "departure_offers", "companies"
  add_foreign_key "departure_offers", "departures"
  add_foreign_key "departure_offers", "travel_packages"
  add_foreign_key "departure_stops", "boarding_points"
  add_foreign_key "departure_stops", "departures"
  add_foreign_key "departures", "buses"
  add_foreign_key "departures", "companies"
  add_foreign_key "departures", "routes"
  add_foreign_key "destinations", "companies"
  add_foreign_key "fare_versions", "departure_offers"
  add_foreign_key "fare_versions", "users", column: "created_by_id"
  add_foreign_key "membership_roles", "memberships"
  add_foreign_key "memberships", "companies"
  add_foreign_key "memberships", "users"
  add_foreign_key "notification_preferences", "memberships"
  add_foreign_key "notifications", "companies"
  add_foreign_key "notifications", "users"
  add_foreign_key "passenger_form_submissions", "departure_stops"
  add_foreign_key "passenger_form_submissions", "passenger_forms"
  add_foreign_key "passenger_forms", "companies"
  add_foreign_key "passenger_forms", "departure_offers"
  add_foreign_key "passenger_forms", "memberships", column: "reseller_membership_id"
  add_foreign_key "passengers", "accommodations"
  add_foreign_key "passengers", "companies"
  add_foreign_key "passengers", "departure_stops"
  add_foreign_key "passengers", "reservations"
  add_foreign_key "platform_roles", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "remittance_allocations", "customer_payments"
  add_foreign_key "remittance_allocations", "remittances"
  add_foreign_key "remittances", "companies"
  add_foreign_key "remittances", "memberships", column: "reseller_membership_id"
  add_foreign_key "remittances", "users", column: "declared_by_id"
  add_foreign_key "remittances", "users", column: "verified_by_id"
  add_foreign_key "reseller_authorizations", "memberships"
  add_foreign_key "reservations", "companies"
  add_foreign_key "reservations", "departure_offers"
  add_foreign_key "reservations", "memberships", column: "seller_membership_id"
  add_foreign_key "reservations", "users", column: "created_by_id"
  add_foreign_key "room_assignment_passengers", "passengers"
  add_foreign_key "room_assignment_passengers", "room_assignments"
  add_foreign_key "room_assignments", "accommodations"
  add_foreign_key "room_assignments", "companies"
  add_foreign_key "room_assignments", "departures"
  add_foreign_key "route_stages", "accommodations"
  add_foreign_key "route_stages", "boarding_points"
  add_foreign_key "route_stages", "routes"
  add_foreign_key "routes", "companies"
  add_foreign_key "seat_allocations", "companies"
  add_foreign_key "seat_allocations", "departures"
  add_foreign_key "seat_allocations", "passengers"
  add_foreign_key "travel_packages", "companies"
  add_foreign_key "travel_packages", "destinations"
end
