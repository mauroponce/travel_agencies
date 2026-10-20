class EnforceTenantForeignKeys < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LINKS = [
    %i[accommodations destination_id destinations],
    %i[travel_packages destination_id destinations],
    %i[departures bus_id buses],
    %i[departures route_id routes],
    %i[departure_offers travel_package_id travel_packages],
    %i[departure_offers departure_id departures],
    %i[departure_offers accommodation_id accommodations],
    %i[passenger_forms departure_offer_id departure_offers],
    %i[passenger_forms reseller_membership_id memberships],
    %i[passenger_forms reservation_id reservations],
    %i[reservations departure_offer_id departure_offers],
    %i[reservations seller_membership_id memberships],
    %i[passengers reservation_id reservations],
    %i[passengers accommodation_id accommodations],
    %i[seat_allocations departure_id departures],
    %i[seat_allocations passenger_id passengers],
    %i[room_assignments departure_id departures],
    %i[room_assignments accommodation_id accommodations],
    %i[customer_payments reservation_id reservations],
    %i[customer_payments received_by_membership_id memberships],
    %i[remittances reseller_membership_id memberships],
    %i[commission_rules reseller_membership_id memberships],
    %i[commission_entries reservation_id reservations],
    %i[commission_entries reseller_membership_id memberships],
    %i[boarding_events departure_id departures],
    %i[boarding_events passenger_id passengers]
  ].freeze

  def up
    violations = LINKS.filter_map do |child, column, parent|
      count = select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM #{quote_table_name(child)} child
        JOIN #{quote_table_name(parent)} parent ON parent.id = child.#{quote_column_name(column)}
        WHERE child.#{quote_column_name(column)} IS NOT NULL
          AND child.company_id <> parent.company_id
      SQL
      "#{child}.#{column}=#{count}" if count.positive?
    end
    if violations.any?
      raise ActiveRecord::MigrationError,
        "Tenant integrity violations detected (#{violations.join(', ')}). Run bin/rails tenant_integrity:audit and repair them before retrying."
    end

    LINKS.map(&:last).uniq.each do |parent|
      add_index parent, %i[id company_id], unique: true, algorithm: :concurrently,
        name: tenant_index_name(parent), if_not_exists: true
    end

    LINKS.each do |child, column, parent|
      add_foreign_key child, parent, column: [ column, :company_id ], primary_key: %i[id company_id],
        name: tenant_foreign_key_name(child, column), validate: false, if_not_exists: true
      validate_foreign_key child, name: tenant_foreign_key_name(child, column)
    end
  end

  def down
    LINKS.reverse_each do |child, column, _parent|
      remove_foreign_key child, name: tenant_foreign_key_name(child, column), if_exists: true
    end
    LINKS.map(&:last).uniq.each do |parent|
      remove_index parent, name: tenant_index_name(parent), algorithm: :concurrently, if_exists: true
    end
  end

  private

  def tenant_index_name(table)
    "uidx_#{table}_id_company"
  end

  def tenant_foreign_key_name(table, column)
    "fk_#{table}_#{column}_tenant"
  end
end
