module Agent
  class SaveImport
    def self.call(import:, acknowledge_duplicates: false)
      workspace = import.agent_workspace
      workspace.with_lock do
        Access.new(workspace).require_commercial!
        import.lock!
        raise ImportReview::Invalid, "El flyer todavía no está listo para confirmar." unless import.status == "completed"
        review = ImportReview.new(import)
        items = review.selected_items
        saved = import.items.where.not(agent_trip_id: nil).includes(:agent_trip).map(&:agent_trip)
        return saved if items.empty? && saved.any?
        raise ImportReview::Invalid, "Seleccioná al menos una salida." if items.empty?
        fingerprints = []
        items.each do |item|
          attributes = review.values(item)
          %w[departs_on returns_on].each do |field|
            next if attributes[field].blank?
            date = Date.iso8601(attributes[field].to_s)
            raise Date::Error unless date.iso8601 == attributes[field].to_s
          rescue Date::Error
            raise ImportReview::Invalid, "Revisá la fecha de #{attributes['title'].presence || 'la salida'}: usá una fecha válida."
          end
          raise ImportReview::Invalid, "Completá la fecha de cada salida seleccionada." if attributes["departs_on"].blank?
          fingerprint = [ attributes["agent_supplier_id"], SupplierMatch.normalize(attributes["destination"]), attributes["departs_on"] ]
          if !acknowledge_duplicates && (review.duplicates(item, attributes).any? || fingerprints.include?(fingerprint))
            raise ImportReview::Invalid, "Hay posibles duplicados. Revisá las coincidencias y confirmá si querés crear otros borradores."
          end
          fingerprints << fingerprint
          attributes["price_cents"] = attributes["price"].present? ? MoneyParser.call(attributes.delete("price")) : nil
          saved << SaveTrip.call(workspace:, attributes:, item:)
        end
        AuditRecorder.call(action: "agent_import.confirmed", auditable: import, changeset: { trip_ids: saved.map(&:id) })
        saved
      end
    end
  end
end
