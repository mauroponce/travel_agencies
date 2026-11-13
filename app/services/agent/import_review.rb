module Agent
  # Review state lives on the existing items, independently of the browser and AI job.
  class ImportReview
    class Invalid < StandardError; end
    FIELDS = (AgentTripRevision::FIELDS - %w[price_cents] + %w[price]).freeze
    PERMITTED_FIELDS = (FIELDS + [ { fares: TripFares::REVIEW_FIELDS } ]).freeze

    def initialize(import)
      @import = import
      @workspace = import.agent_workspace
    end

    def values(item)
      data = item.extracted.slice(*AgentTripRevision::FIELDS)
      data["departs_on"] = DepartureDate.call(value: data["departs_on"],
        text: item.extracted["departure_text"].presence || item.extracted.dig("evidence", "departs_on"),
        today: (@import.started_at || @import.created_at).in_time_zone(@workspace.timezone).to_date)
      data["price"] = data["price_cents"] && format("%.2f", BigDecimal(data["price_cents"].to_s) / 100)
      matches = SupplierMatch.candidates(suppliers, item.extracted["supplier_name"])
      data["agent_supplier_id"] = matches.first.id if matches.one?
      data = data.except("price_cents").merge(item.review_data.slice(*FIELDS))
      data["currency"] = data["currency"].presence || "ARS"
      data["price_unit"] = "per_person"
      source_fares = item.review_data.key?("fares") ? item.review_data["fares"] : item.extracted["fares"]
      data["fares"] = TripFares.review(source_fares, defaults: data)
      data
    end

    def save!(rows)
      @workspace.with_lock do
        Access.new(@workspace).require_commercial!
        @import.lock!
        raise Invalid, "Esperá a que termine el procesamiento del flyer." unless @import.status == "completed"
        raise Invalid, "Se permiten hasta 50 salidas por importación." unless rows.is_a?(Array) && rows.size <= 50
        rows.each do |row|
          item = if row["id"].present?
            @import.items.find(row["id"])
          else
            key = row["client_key"].to_s
            raise Invalid, "Falta identificar la salida nueva." unless key.match?(/\A[\w-]{1,80}\z/)
            existing = @import.items.find_by("review_data ->> '_client_key' = ?", key)
            existing || begin
              raise Invalid, "Se permiten hasta 50 salidas por importación." if @import.items.count >= 50
              template = @import.items.find(row["template_id"])
              extracted = template.extracted.except("departure_text", "departs_on", "returns_on")
              extracted["evidence"] = template.extracted.fetch("evidence", {}).except("departs_on", "returns_on")
              @import.items.create!(agent_workspace: @workspace, position: @import.items.maximum(:position).to_i + 1,
                extracted:, review_data: { "_client_key" => key })
            end
          end
          next if item.agent_trip_id
          fields = row.fetch("values", {}).slice(*FIELDS, "fares")
          fields["price_unit"] = "per_person"
          if fields["fares"].present?
            fields["fares"] = TripFares.review(fields["fares"], defaults: fields)
            previous = values(item)
            if fields["fares"] == previous["fares"]
              index = previous["fares"].index { |fare| fare["price_basis"] == previous["price_basis"] && fare["currency"] == previous["currency"] && fare["price"].to_s == previous["price"].to_s } || 0
              %w[price currency price_unit price_basis].each do |key|
                fields["fares"][index][key] = fields[key] if fields.key?(key) && fields[key] != previous[key]
              end
            end
          end
          if fields["agent_supplier_id"].present?
            @workspace.agent_suppliers.find(fields["agent_supplier_id"])
          end
          item.update!(review_data: item.review_data.merge(fields).merge(
            "_selected" => ActiveModel::Type::Boolean.new.cast(row["selected"]),
            "_overrides" => Array(row["overrides"]) & (FIELDS + [ "fares" ])))
        end
      end
    end

    def selected_items
      @import.items.reload.reject { |item| item.review_data["_selected"] == false || item.agent_trip_id.present? }
    end

    def duplicates(item, data = values(item))
      return [] if data.values_at("agent_supplier_id", "destination", "departs_on").any?(&:blank?)
      date = Date.iso8601(data["departs_on"].to_s)
      @workspace.agent_trips.joins(:current_revision)
        .where(agent_trip_revisions: { agent_supplier_id: data["agent_supplier_id"], departs_on: date })
        .where("unaccent(lower(agent_trip_revisions.destination)) = unaccent(lower(?))", data["destination"].to_s.strip)
        .order(created_at: :desc, id: :desc).limit(10).map { |trip| { id: trip.id, title: trip.current_revision.title } }
    rescue Date::Error
      []
    end

    def payload
      @import.items.reload.map do |item|
        data = values(item)
        { id: item.id, client_key: item.review_data["_client_key"], program: item.extracted["program_key"].presence || legacy_program(item),
          values: data, selected: item.review_data["_selected"] != false,
          overrides: item.review_data.fetch("_overrides", []), supplier_name: item.extracted["supplier_name"],
          supplier_candidates: SupplierMatch.candidates(suppliers, item.extracted["supplier_name"]).map(&:id),
          warnings: item.extracted.fetch("warnings", []), departure_text: item.extracted["departure_text"],
          evidence: item.extracted.fetch("evidence", {}), trip_id: item.agent_trip_id, duplicates: duplicates(item, data) }
      end
    end

    private

    def suppliers = @suppliers ||= @workspace.agent_suppliers.order(:name, :id).to_a

    def legacy_program(item)
      Digest::SHA256.hexdigest(item.extracted.slice("supplier_name", "title", "destination", "hotel").to_json).first(16)
    end
  end
end
