class MoneyParser
  class InvalidAmount < ArgumentError; end

  def self.call(value)
    normalized = value.to_s.strip.delete("$\u00A0 ")
    normalized = if normalized.include?(",")
      normalized.delete(".").tr(",", ".")
    else
      normalized
    end

    amount = BigDecimal(normalized)
    cents = amount * 100
    raise InvalidAmount, "El importe debe tener como máximo dos decimales" unless cents.frac.zero?

    cents.to_i
  rescue ArgumentError
    raise InvalidAmount, "Ingresá un importe válido en pesos"
  end
end
