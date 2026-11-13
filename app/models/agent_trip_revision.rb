class AgentTripRevision < ApplicationRecord
  include AgentCommercialRecord
  FIELDS = %w[agent_supplier_id title destination departs_on returns_on duration_days duration_nights description price_cents currency price_unit price_basis hotel meal_plan transport departure_location included_services excluded_services conditions].freeze
  CURRENCIES = %w[ARS USD].freeze
  CURRENCY_LABELS = { "ARS" => "Pesos Argentinos", "USD" => "Dólares" }.freeze
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
  before_validation { self.currency = "ARS" if currency.blank? }
  validate :validate_fares
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
    fares.each_with_index do |fare, index|
      next unless fare.is_a?(Hash)
      errors.add(:fares, "tarifa #{index + 1}: completá precio, moneda y unidad antes de publicar") unless fare["price_cents"].to_i.positive? && CURRENCIES.include?(fare["currency"]) && PRICE_UNITS.key?(fare["price_unit"])
    end if fares.is_a?(Array)
    errors.add(:departs_on, "ya pasó") if departs_on && departs_on < Date.current
    errors.add(:agent_supplier, "está pausado") unless agent_supplier.active?
    errors.add(:agent_workspace, "está suspendido") unless agent_workspace.active?
    errors.add(:agent_workspace, "requiere un WhatsApp válido") unless agent_workspace.whatsapp.match?(/\A[1-9]\d{7,14}\z/)
    raise ActiveRecord::RecordInvalid, self if errors.any?
  end

  private

  def validate_fares
    unless fares.is_a?(Array) && fares.size <= Agent::TripFares::MAX_FARES
      return errors.add(:fares, "deben ser una lista de hasta #{Agent::TripFares::MAX_FARES} tarifas")
    end
    fares.each_with_index do |fare, index|
      valid = fare.is_a?(Hash) && (fare.keys - Agent::TripFares::STORED_FIELDS).empty?
      if valid
        valid &&= fare["label"].is_a?(String) && fare["label"].length.between?(1, 200)
        valid &&= CURRENCIES.include?(fare["currency"])
        valid &&= fare["price_unit"].blank? || PRICE_UNITS.key?(fare["price_unit"])
        %w[price_cents list_price_cents].each { |key| valid &&= fare[key].nil? || (fare[key].is_a?(Integer) && fare[key].between?(0, 10**14)) }
        %w[price_basis hotel conditions].each { |key| valid &&= fare[key].nil? || (fare[key].is_a?(String) && fare[key].length <= (key == "conditions" ? 10000 : 500)) }
      end
      errors.add(:fares, "tarifa #{index + 1}: revisá base, precio y moneda") unless valid
    end
  end
end
