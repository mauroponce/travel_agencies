class PassengerFormSubmission < ApplicationRecord
  belongs_to :passenger_form
  belongs_to :departure_stop
  encrypts :full_name
  encrypts :document_number
  encrypts :notes
  validates :full_name, :document_number, :document_last4, :nationality, presence: true
end
