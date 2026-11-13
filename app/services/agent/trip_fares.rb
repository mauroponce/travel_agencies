module Agent
  # Fare options belong to a program/revision; they never multiply departures.
  class TripFares
    class Invalid < ::MoneyParser::InvalidAmount; end
    STORED_FIELDS = %w[label price_cents list_price_cents currency price_unit price_basis hotel conditions].freeze
    REVIEW_FIELDS = %w[label price list_price currency price_unit price_basis hotel conditions].freeze
    PRICE_FIELDS = %w[price_cents currency price_unit price_basis].freeze
    MAX_FARES = 20

    def self.default_label(basis)
      text = I18n.transliterate(basis.to_s).downcase
      return "Base triple / cuádruple" if text.include?("triple") && text.include?("cuadruple")
      return "Base cuádruple" if text.include?("cuadruple")
      return "Base triple" if text.include?("triple")
      return "Base single" if text.include?("single") || text.include?("individual")
      "Base doble"
    end

    def self.review(fares, defaults: {})
      entries = fares.is_a?(Hash) ? fares.values : fares
      entries = [ defaults ] if entries.blank?
      raise Invalid, "Revisá las tarifas: se permiten entre 1 y #{MAX_FARES} opciones." unless entries.is_a?(Array) && entries.size.between?(1, MAX_FARES)
      entries.map do |fare|
        raise Invalid, "Revisá los datos de cada tarifa." unless fare.is_a?(Hash)
        label = fare["label"].presence || default_label(fare["price_basis"].presence || defaults["price_basis"])
        fare.slice(*REVIEW_FIELDS).merge(
          "label" => label, "price_basis" => fare["price_basis"].presence || label,
          "currency" => fare["currency"].presence || defaults["currency"].presence || "ARS",
          "price_unit" => "per_person",
          "price" => review_price(fare, defaults),
          "list_price" => fare.key?("list_price") ? fare["list_price"] : amount(fare["list_price_cents"]))
      end
    end

    def self.review_price(fare, defaults)
      return fare["price"] if fare.key?("price")
      return amount(fare["price_cents"]) if fare.key?("price_cents")
      defaults.key?("price") ? defaults["price"] : amount(defaults["price_cents"])
    end

    def self.normalize(fares, defaults: {})
      review(fares, defaults:).map do |fare|
        fare.except("price", "list_price").merge(
          "price_cents" => fare["price"].present? ? MoneyParser.call(fare["price"]) : nil,
          "list_price_cents" => fare["list_price"].present? ? MoneyParser.call(fare["list_price"]) : nil)
      end
    end

    def self.primary(fares)
      priced = fares.select { |fare| fare["price_cents"].is_a?(Integer) }
      return fares.first if priced.empty?
      priced.map { |fare| fare.values_at("currency", "price_unit") }.uniq.one? ? priced.min_by { |fare| fare["price_cents"] } : priced.first
    end

    def self.apply!(fields, fares)
      fields["fares"] = fares
      if (main = primary(fares))
        fields.merge!(main.slice(*PRICE_FIELDS))
        fields["hotel"] = main["hotel"] if main["hotel"].present? && fields["hotel"].blank?
      end
      fields
    end

    def self.amount(cents)
      cents && format("%.2f", BigDecimal(cents.to_s) / 100)
    end
  end
end
