class BoardingEventsController < ApplicationController
  before_action -> { require_role!("coordinator") }

  def create
    sync
  end

  def sync
    departure = current_company.departures.find(params[:departure_id])
    commands = params.fetch(:commands, []).map { |command| command.respond_to?(:to_unsafe_h) ? command.to_unsafe_h : command }
    results = Boarding::Sync.call(departure:, membership: current_membership, commands:)
    render json: { results: }
  end
end
