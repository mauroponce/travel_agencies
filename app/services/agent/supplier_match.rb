module Agent
  class SupplierMatch
    COMMERCIAL_WORDS = %w[viaje viajes turismo turistica turistico travel travels tour tours operador operadora mayorista sa srl sas].freeze

    def self.normalize(name)
      normalized = I18n.transliterate(name.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip.split.join(" ")
      # Flyers often append an agency registration number to the commercial name.
      normalized.sub(/\s+(?:leg|legajo|licencia|evt)(?:\s+(?:n|nro|no))?\s+\d+\z/, "").sub(/\s+s (?:a(?: s)?|r l)\z/, "")
    end

    def self.identity(name)
      normalize(name).split.reject { |word| COMMERCIAL_WORDS.include?(word) }.join(" ")
    end

    def self.candidates(suppliers, name)
      return [] if name.blank?
      exact = suppliers.select { |supplier| normalize(supplier.name) == normalize(name) }
      return exact if exact.any?
      compact = suppliers.select { |supplier| normalize(supplier.name).delete(" ") == normalize(name).delete(" ") }
      return compact if compact.any?
      key = identity(name).delete(" ")
      return [] if key.blank?
      suppliers.select { |supplier| identity(supplier.name).delete(" ") == key }
    end

    def self.find_or_create!(workspace:, name:)
      workspace.with_lock do
        Access.new(workspace).require_commercial!
        matches = candidates(workspace.agent_suppliers.to_a, name)
        if matches.many?
          invalid = workspace.agent_suppliers.new(name:)
          invalid.errors.add(:name, "coincide con varias empresas. Seleccioná una de las existentes.")
          raise ActiveRecord::RecordInvalid, invalid
        end
        return matches.first if matches.one?
        supplier = workspace.agent_suppliers.create!(name:)
        AuditRecorder.call(action: "agent_supplier.created", auditable: supplier)
        supplier
      end
    end
  end
end
