class AddFaresToAgentTripRevisions < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_trip_revisions, :fares, :jsonb, default: [], null: false
  end
end
