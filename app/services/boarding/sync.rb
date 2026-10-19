module Boarding
  class Sync
    def self.call(departure:, membership:, commands:)
      new(departure:, membership:, commands:).call
    end

    def initialize(departure:, membership:, commands:)
      @departure = departure
      @membership = membership
      @commands = commands
    end

    def call
      assigned = @departure.departure_assignments.exists?(membership: @membership)
      raise Pundit::NotAuthorizedError unless assigned && @membership.role?("coordinator")

      @commands.map { |command| apply(command.symbolize_keys) }
    end

    private

    def apply(command)
      existing = BoardingEvent.find_by(command_id: command.fetch(:command_id))
      return { command_id: command[:command_id], result: "duplicate", status: existing.status } if existing

      passenger = Passenger.with_active_reservations.where(company: @membership.company).joins(reservation: :departure_offer)
        .where(departure_offers: { departure_id: @departure.id }).find(command.fetch(:passenger_id))

      passenger.reservation.with_lock do
        raise ActiveRecord::RecordNotFound unless passenger.reservation.status == "confirmed"

        passenger.with_lock do
          next conflict(command, passenger) if passenger.lock_version != command.fetch(:base_version).to_i

          event = BoardingEvent.create!(company: @membership.company, departure: @departure, passenger:,
            recorded_by: @membership.user, command_id: command[:command_id], status: command.fetch(:desired_status),
            base_version: command[:base_version], occurred_at: command[:occurred_at] || Time.current, notes: command[:notes])
          passenger.touch
          { command_id: command[:command_id], result: "applied", status: event.status, version: passenger.lock_version }
        end
      end
    rescue ActiveRecord::RecordNotUnique
      { command_id: command[:command_id], result: "duplicate" }
    end

    def conflict(command, passenger)
      { command_id: command[:command_id], result: "conflict", server_status: passenger.boarding_status,
       version: passenger.lock_version }
    end
  end
end
