module Agent
  class AiContract
    VERSION = "agent-v4"
    class Invalid < StandardError; end
    TEXT_FIELDS = (AgentTripRevision::FIELDS - %w[agent_supplier_id price_cents duration_days duration_nights]).freeze
    SEARCH_TEXT = %w[destination region from to min_price max_price currency price_unit meal_plan transport departure_location].freeze
    SEARCH_INTEGER = %w[min_days max_days].freeze

    def self.nullable(type) = { type: [ type, "null" ] }
    def self.departure_properties
      { "label" => { type: "string", description: "Una sola salida tal como figura en el archivo, por ejemplo: 3 de febrero. Si falta año, la fecha ISO usa su próxima ocurrencia desde hoy." },
        "departs_on" => nullable("string"), "returns_on" => nullable("string") }
    end
    def self.trip_properties
      TEXT_FIELDS.index_with { nullable("string") }.merge("price_cents" => nullable("integer"), "duration_days" => nullable("integer"), "duration_nights" => nullable("integer"),
        "supplier_name" => nullable("string"),
        "departures" => { type: [ "array", "null" ], description: "Todas las salidas de este mismo viaje, una entrada por fecha. null si no se informan salidas.",
          items: { type: "object", properties: departure_properties, required: departure_properties.keys, additionalProperties: false } },
        "warnings" => { type: "array", items: { type: "string" } },
        "evidence" => { type: "array", items: { type: "object", properties: { "field" => { type: "string" }, "quote" => { type: "string" } }, required: %w[field quote], additionalProperties: false } })
    end
    def self.search_properties
      SEARCH_TEXT.index_with { nullable("string") }.merge(SEARCH_INTEGER.index_with { nullable("integer") })
    end
    def self.schema(kind)
      if kind == "import"
        properties = trip_properties
        { type: "object", properties: { trips: { type: "array", maxItems: 50, items: { type: "object", properties:, required: properties.keys, additionalProperties: false } } }, required: [ "trips" ], additionalProperties: false }
      else
        { type: "object", properties: { filters: { type: "object", properties: search_properties, required: search_properties.keys, additionalProperties: false }, interpretation: { type: "array", items: { type: "string" } } }, required: %w[filters interpretation], additionalProperties: false }
      end
    end

    # Flash-Lite currently rejects maxItems in this nested extraction schema.
    # Keep the 50-item limit in strict local validation instead.
    def self.provider_schema(kind)
      definition = schema(kind)
      definition[:properties][:trips].delete(:maxItems) if kind == "import"
      definition
    end
    def self.parse(kind, text, today: Date.current)
      raise Invalid, "response_size" if text.bytesize > 1.megabyte
      data = JSON.parse(text)
      if kind == "import"
        object!(data, %w[trips])
        raise Invalid, "trips" unless data["trips"].is_a?(Array) && data["trips"].length.between?(1, 50)
        data["trips"] = data["trips"].flat_map do |trip|
          object!(trip, trip_properties.keys)
          typed_fields!(trip, TEXT_FIELDS + [ "supplier_name" ], %w[price_cents duration_days duration_nights])
          string_array!(trip["warnings"])
          raise Invalid, "evidence" unless trip["evidence"].is_a?(Array) && trip["evidence"].size <= 100
          trip["evidence"].each { |e| object!(e, %w[field quote]); typed_fields!(e, %w[field quote], []) }
          trip["evidence"] = trip["evidence"].to_h { |e| [ e["field"], e["quote"] ] }
          dates!(trip, %w[departs_on returns_on])
          raise Invalid, "currency" if trip["currency"].present? && !AgentTripRevision::CURRENCIES.include?(trip["currency"])
          raise Invalid, "price_unit" if trip["price_unit"].present? && !AgentTripRevision::PRICE_UNITS.key?(trip["price_unit"])
          raise Invalid, "dates" if trip["departs_on"] && trip["returns_on"] && trip["returns_on"] < trip["departs_on"] && trip["warnings"].empty?
          expand_departures(trip, today:)
        end
        raise Invalid, "trips" if data["trips"].size > 50
      else
        object!(data, %w[filters interpretation])
        object!(data["filters"], search_properties.keys)
        typed_fields!(data["filters"], SEARCH_TEXT, SEARCH_INTEGER)
        dates!(data["filters"], %w[from to])
        string_array!(data["interpretation"])
        %w[min_price max_price].each do |field|
          value = data["filters"][field]
          raise Invalid, "price" if value && (!value.match?(/\A\d+(?:\.\d{1,2})?\z/) || MoneyParser.call(value).negative?)
        end
        raise Invalid, "currency" if data["filters"]["currency"].present? && !AgentTripRevision::CURRENCIES.include?(data["filters"]["currency"])
        raise Invalid, "price_unit" if data["filters"]["price_unit"].present? && !AgentTripRevision::PRICE_UNITS.key?(data["filters"]["price_unit"])
        data["filters"].compact!
      end
      data
    rescue JSON::ParserError, Date::Error, MoneyParser::InvalidAmount
      raise Invalid, "invalid_response"
    end
    def self.object!(value, keys)
      raise Invalid, "object" unless value.is_a?(Hash) && value.keys.sort == keys.sort
    end
    def self.expand_departures(trip, today:)
      departures = trip["departures"]
      if departures.nil?
        trip["departs_on"] = DepartureDate.call(value: trip["departs_on"], text: trip.dig("evidence", "departs_on"), today:)
        raise Invalid, "dates" if trip["departs_on"] && trip["returns_on"] && trip["returns_on"] < trip["departs_on"] && trip["warnings"].empty?
        return [ trip.except("departures") ]
      end
      raise Invalid, "departures" unless departures.is_a?(Array) && departures.length.between?(1, 50)

      departures.map do |departure|
        object!(departure, departure_properties.keys)
        typed_fields!(departure, departure_properties.keys, [])
        label = departure["label"]
        raise Invalid, "departure_label" unless label.present? && label.length <= 300
        dates!(departure, %w[departs_on returns_on])
        candidate = trip.except("departures").deep_dup
        candidate.merge!(departure.slice("departs_on", "returns_on"))
        candidate["departs_on"] = DepartureDate.call(value: candidate["departs_on"], text: label, today:)
        raise Invalid, "dates" if candidate["departs_on"] && candidate["returns_on"] && candidate["returns_on"] < candidate["departs_on"] && candidate["warnings"].empty?
        candidate["departure_text"] = label
        candidate["evidence"]["departs_on"] = label
        if candidate["departs_on"].nil?
          candidate["warnings"] << "Confirmá la fecha completa de la salida «#{label}»: el flyer no permite determinarla con certeza."
        end
        candidate
      end
    end
    def self.typed_fields!(data, strings, integers)
      strings.each { |field| raise Invalid, field unless data[field].nil? || (data[field].is_a?(String) && data[field].length <= 10000) }
      integers.each { |field| raise Invalid, field unless data[field].nil? || (data[field].is_a?(Integer) && data[field].between?(0, 10**14)) }
    end
    def self.string_array!(value)
      raise Invalid, "array" unless value.is_a?(Array) && value.size <= 100 && value.all? { |item| item.is_a?(String) && item.length <= 2000 }
    end
    def self.dates!(data, fields)
      fields.each { |field| Date.iso8601(data[field]) if data[field] }
    end
  end
end
