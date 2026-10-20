class AddPaginationIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :companies, :name, if_not_exists: true
    add_index :departure_offers, [ :company_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :departures, [ :company_id, :departs_at ], if_not_exists: true
    add_index :travel_packages, [ :company_id, :name ], if_not_exists: true
    add_index :reservations, [ :company_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :reservations, [ :seller_membership_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :customer_payments, [ :company_id, :received_on, :created_at ],
      order: { received_on: :desc, created_at: :desc }, if_not_exists: true
    add_index :customer_payments, [ :received_by_membership_id, :received_on ],
      order: { received_on: :desc }, if_not_exists: true
    add_index :remittances, [ :company_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :remittances, [ :reseller_membership_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :passenger_forms, [ :company_id, :reseller_membership_id, :created_at ],
      order: { created_at: :desc }, if_not_exists: true
    add_index :memberships, [ :company_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :company_invitations, [ :company_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :commission_entries, [ :company_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :commission_entries, [ :reseller_membership_id, :created_at ],
      order: { created_at: :desc }, if_not_exists: true
    add_index :notifications, [ :user_id, :company_id, :created_at ], order: { created_at: :desc }, if_not_exists: true
    add_index :buses, [ :company_id, :name ], if_not_exists: true
    add_index :boarding_points, [ :company_id, :name ], if_not_exists: true
    add_index :routes, [ :company_id, :name ], if_not_exists: true
  end
end
