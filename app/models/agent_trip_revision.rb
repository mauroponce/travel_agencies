class AgentTripRevision < ApplicationRecord
  FIELDS = %w[agent_supplier_id title destination region departs_on returns_on duration_days duration_nights description price_cents currency price_unit price_basis hotel meal_plan transport departure_location included_services excluded_services conditions].freeze
  CURRENCIES = %w[ARS USD EUR BRL].freeze
  PRICE_UNITS = { "per_person" => "Por persona", "per_group" => "Por grupo", "per_room" => "Por habitación" }.freeze
  MEAL_PLANS = [ "Desayuno", "Media pensión", "Pensión completa", "Todo incluido", "Sin comidas" ].freeze
  belongs_to :agent_workspace
  belongs_to :agent_trip
  belongs_to :agent_supplier
  has_one_attached :cover
  has_one_attached :flyer_source
  has_one :agent_import_item, dependent: :restrict_with_error
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :duration_nights, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :duration_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :currency, inclusion: { in: CURRENCIES }, allow_blank: true
  validates :price_unit, inclusion: { in: PRICE_UNITS.keys }, allow_blank: true
  validates :title, :destination, :region, :hotel, :meal_plan, :transport, :departure_location, length: { maximum: 300 }
  validate do
    errors.add(:agent_supplier, "pertenece a otro espacio") unless agent_supplier&.agent_workspace_id == agent_workspace_id
    errors.add(:agent_trip, "pertenece a otro espacio") unless agent_trip&.agent_workspace_id == agent_workspace_id
    errors.add(:returns_on, "debe ser posterior a la salida") if returns_on && departs_on && returns_on < departs_on
    errors.add(:base, "Las revisiones son inmutables") if persisted? && changed?
  end

  def validate_for_publication!
    valid?
    %i[title destination departs_on currency price_unit].each { |key| errors.add(key, "es obligatorio para publicar") if public_send(key).blank? }
    errors.add(:price_cents, "debe ser mayor a cero") unless price_cents.to_i.positive?
    errors.add(:departs_on, "ya pasó") if departs_on && departs_on < Date.current
    errors.add(:agent_supplier, "está pausado") unless agent_supplier.active?
    errors.add(:agent_workspace, "está suspendido") unless agent_workspace.active?
    errors.add(:agent_workspace, "requiere un WhatsApp válido") unless agent_workspace.whatsapp.match?(/\A[1-9]\d{7,14}\z/)
    raise ActiveRecord::RecordInvalid, self if errors.any?
  end
end
