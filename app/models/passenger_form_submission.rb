class PassengerFormSubmission < ApplicationRecord
  belongs_to :passenger_form
  belongs_to :departure_stop
  encrypts :full_name
  encrypts :document_number
  encrypts :notes
  validates :full_name, :document_number, :document_last4, :nationality, presence: true
  validate :departure_stop_matches_form

  private

  def departure_stop_matches_form
    return unless passenger_form && departure_stop

    expected_departure_id = passenger_form.departure_offer.departure_id
    errors.add(:departure_stop, "no pertenece a la salida del formulario") if departure_stop.departure_id != expected_departure_id
  end
end
