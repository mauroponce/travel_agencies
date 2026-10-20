namespace :tenant_integrity do
  DIRECT_LINKS = {
    "accommodations" => %w[destination],
    "travel_packages" => %w[destination],
    "departures" => %w[bus route],
    "departure_offers" => %w[travel_package departure accommodation],
    "passenger_forms" => %w[departure_offer reseller_membership reservation],
    "reservations" => %w[departure_offer seller_membership],
    "passengers" => %w[reservation accommodation],
    "seat_allocations" => %w[departure passenger],
    "room_assignments" => %w[departure accommodation],
    "customer_payments" => %w[reservation received_by_membership],
    "remittances" => %w[reseller_membership],
    "commission_rules" => %w[reseller_membership],
    "commission_entries" => %w[reservation reseller_membership],
    "boarding_events" => %w[departure passenger]
  }.freeze

  desc "List records whose direct associations cross company boundaries"
  task audit: :environment do
    failures = []
    DIRECT_LINKS.each do |table, associations|
      model = table.classify.constantize
      model.find_each do |record|
        associations.each do |association|
          target = record.public_send(association)
          next unless target
          target_company_id = target.respond_to?(:company_id) ? target.company_id : target.company&.id
          failures << "#{table}:#{record.id} #{association}=#{target.id}" if target_company_id != record.company_id
        end
      end
    end
    RouteStage.includes(:route, :boarding_point, :accommodation).find_each do |stage|
      failures << "route_stages:#{stage.id} boarding_point=#{stage.boarding_point_id}" if stage.boarding_point &&
        stage.boarding_point.company_id != stage.route.company_id
      failures << "route_stages:#{stage.id} accommodation=#{stage.accommodation_id}" if stage.accommodation &&
        stage.accommodation.company_id != stage.route.company_id
    end
    DepartureStop.includes(:departure, :boarding_point).find_each do |stop|
      failures << "departure_stops:#{stop.id} boarding_point=#{stop.boarding_point_id}" if
        stop.departure.company_id != stop.boarding_point.company_id
    end
    DepartureAssignment.includes(:departure, :membership).find_each do |assignment|
      failures << "departure_assignments:#{assignment.id} membership=#{assignment.membership_id}" if
        assignment.departure.company_id != assignment.membership.company_id
    end
    RoomAssignmentPassenger.includes(:room_assignment, passenger: { reservation: :departure_offer }).find_each do |link|
      passenger = link.passenger
      room = link.room_assignment
      valid = passenger.company_id == room.company_id && passenger.accommodation_id == room.accommodation_id &&
        passenger.reservation.departure_offer.departure_id == room.departure_id
      failures << "room_assignment_passengers:#{link.id} passenger=#{passenger.id}" unless valid
    end
    RemittanceAllocation.includes(:remittance, :customer_payment).find_each do |allocation|
      valid = allocation.remittance.company_id == allocation.customer_payment.company_id &&
        allocation.remittance.reseller_membership_id == allocation.customer_payment.received_by_membership_id
      failures << "remittance_allocations:#{allocation.id} payment=#{allocation.customer_payment_id}" unless valid
    end
    puts failures.any? ? failures.join("\n") : "Tenant integrity audit: OK"
    abort "Found #{failures.size} tenant integrity violation(s)" if failures.any?
  end

  desc "Repair one record's company from an explicit trusted association (TABLE, ID, ASSOCIATION)"
  task :repair_company, %i[table id association] => :environment do |_task, args|
    associations = DIRECT_LINKS.fetch(args[:table]) { abort "Unsupported table" }
    abort "Unsupported association" unless associations.include?(args[:association])
    record = args[:table].classify.constantize.find(args[:id])
    target = record.public_send(args[:association]) || abort("Association is empty")
    company_id = target.respond_to?(:company_id) ? target.company_id : target.company&.id
    record.update!(company_id:)
    puts "Updated #{args[:table]}:#{record.id} to company #{company_id} after all model validations passed"
  end
end
