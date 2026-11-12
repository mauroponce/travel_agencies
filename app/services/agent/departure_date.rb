module Agent
  class DepartureDate
    MONTHS = %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre].each_with_index.to_h { |month, index| [ month, index + 1 ] }.merge("setiembre" => 9).freeze

    def self.call(value: nil, text: nil, today: Date.current)
      return value if value.present?
      label = text.to_s.strip.downcase.sub(/\Asalida\s*:?\s*/, "")
      if (match = label.match(/\A(\d{1,2})\s+(?:de\s+)?(#{MONTHS.keys.join('|')})(?:\s+(?:de(?:l)?\s+)?(\d{4}))?\z/))
        day, month, year = match[1].to_i, MONTHS.fetch(match[2]), match[3]&.to_i
      elsif (match = label.match(/\A(\d{1,2})[\/.\-](\d{1,2})(?:[\/.\-](\d{4}))?\z/))
        day, month, year = match[1].to_i, match[2].to_i, match[3]&.to_i
      else
        return
      end

      if year
        Date.new(year, month, day).iso8601
      else
        year = today.year
        year += 1 if month < today.month || (month == today.month && day < today.day)
        Date.new(year, month, day).iso8601
      end
    rescue Date::Error
      nil
    end
  end
end
