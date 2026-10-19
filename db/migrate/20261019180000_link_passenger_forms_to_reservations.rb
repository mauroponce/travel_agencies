class LinkPassengerFormsToReservations < ActiveRecord::Migration[8.1]
  def change
    add_reference :passenger_forms, :reservation, type: :uuid, foreign_key: true, index: { unique: true }
  end
end
