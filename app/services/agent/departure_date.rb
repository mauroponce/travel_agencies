module Agent
  class DepartureDate
    MONTHS = %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre].each_with_index.to_h { |month, index| [ month, index + 1 ] }.merge("setiembre" => 9).freeze

    # Some providers return a grouped list despite the single-departure schema.
    # Expand only complete day/month groups; explicit travel ranges need review.
    def self.labels(text)
      label = text.to_s.strip.downcase.sub(/\Asalida\s*:?\s*/, "")
      return [ text ] if label.match?(/\b(?:del|desde|hasta|al)\b/)
      pattern = /(\d{1,2}(?:\s*[,y-]\s*\d{1,2})*)\s+(?:de\s+)?(#{MONTHS.keys.join('|')})(?:\s+(?:de(?:l)?\s+)?(\d{4}))?/
      groups = label.scan(pattern)
      return [ text ] if groups.empty? || label.gsub(pattern, "").gsub(/[\s,;y-]/, "").present?
      expanded = groups.flat_map do |days, month, year|
        days.split(/\s*[,y-]\s*/).map { |day| "#{day} de #{month}#{" de #{year}" if year}" }
      end
      expanded.many? ? expanded : [ text ]
    end

    def self.call(value: nil, text: nil, today: Date.current)
      label = text.to_s.strip.downcase.sub(/\Asalida\s*:?\s*/, "")
      # Original evidence takes precedence over an ISO year guessed by the model.
      return Date.iso8601(value.to_s).iso8601 if label.blank? && value.present?
      if label.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        return Date.iso8601(label).iso8601
      elsif (match = label.match(/\A(\d{1,2})\s+(?:de\s+)?(#{MONTHS.keys.join('|')})(?:\s+(?:de(?:l)?\s+)?(\d{4}))?\z/))
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
        year += 1 if month < today.month
        Date.new(year, month, day).iso8601
      end
    rescue Date::Error
      nil
    end
  end
end
