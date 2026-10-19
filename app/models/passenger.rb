class Passenger < ApplicationRecord
  belongs_to :company
  belongs_to :reservation
  belongs_to :departure_stop
  belongs_to :accommodation
  has_one :seat_allocation, dependent: :destroy
  has_many :boarding_events, dependent: :restrict_with_error

  encrypts :full_name
  encrypts :document_number
  encrypts :notes
  validates :full_name, :document_number, :document_last4, :nationality, presence: true
  validate :records_share_reservation_scope

  def masked_document
    "••••#{document_last4}"
  end

  def boarding_status
    boarding_events.order(created_at: :desc).pick(:status) || "pending"
  end

  scope :with_active_reservations, -> { joins(:reservation).where.not(reservations: { status: "cancelled" }) }

  private

  def records_share_reservation_scope
    return unless reservation && departure_stop && accommodation
    errors.add(:reservation, "debe pertenecer a la empresa") if reservation.company_id != company_id
    errors.add(:departure_stop, "no pertenece a la salida reservada") if departure_stop.departure_id != reservation.departure_offer.departure_id
    errors.add(:accommodation, "debe pertenecer a la empresa") if accommodation.company_id != company_id
  end
end
