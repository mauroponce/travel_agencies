module Agent
  class PublicCatalogQuery
    FILTERS = (CatalogQuery::FILTERS + %w[month duration destination_query]).freeze
    DURATIONS = { "4" => [ "max_days", "4" ], "6" => [ "max_days", "6" ], "7" => [ "min_days", "7" ] }.freeze

    attr_reader :filters

    def initialize(workspace:, filters: {}, owner_view: false)
      @workspace = workspace
      @owner_view = owner_view
      @filters = filters.to_h.stringify_keys.slice(*FILTERS).reject { |_key, value| value.blank? }
      @filters.delete("destination_query") if @filters["destination"].present?
      @filters["sort"] = { "price" => "price_asc", "az" => "destination_asc" }.fetch(@filters["sort"], @filters["sort"]) if @filters["sort"]
    end

    def trips
      case filters["sort"]
      when "destination_asc"
        scope.reorder(Arel.sql("unaccent(lower(agent_trip_revisions.destination)) ASC NULLS LAST, agent_trip_revisions.departs_on ASC NULLS LAST, agent_trips.id ASC"))
      when "price_asc", "price_desc"
        return scope unless price_sortable?
        direction = filters["sort"] == "price_desc" ? "DESC" : "ASC"
        scope.reorder(Arel.sql("agent_trip_revisions.price_cents #{direction} NULLS LAST, agent_trips.id ASC"))
      else
        scope
      end
    end

    def price_sortable?
      pairs = @price_pairs ||= scope.except(:includes, :order).distinct.pluck("agent_trip_revisions.currency", "agent_trip_revisions.price_unit")
      pairs.one? && pairs.first.all?(&:present?)
    end

    def price_sort_warning?
      %w[price_asc price_desc].include?(filters["sort"]) && !price_sortable?
    end

    def destinations
      options.except(:includes, :order).distinct.order("agent_trip_revisions.destination").pluck("agent_trip_revisions.destination").reject(&:blank?)
    end

    def transports
      options.except(:includes, :order).distinct.order("agent_trip_revisions.transport").pluck("agent_trip_revisions.transport").reject(&:blank?)
    end

    def months
      expression = Arel.sql("date_trunc('month', agent_trip_revisions.departs_on)::date")
      options.except(:includes, :order).where.not(agent_trip_revisions: { departs_on: nil }).distinct.order(expression).pluck(expression)
    end

    private

    def options
      @options ||= CatalogQuery.call(workspace: @workspace, public_view: !@owner_view)
    end

    def scope
      @scope ||= begin
        criteria = filters.except("month", "duration", "destination_query", "destination", "sort")
        criteria["destination"] = filters["destination_query"] if filters["destination_query"].present?
        records = CatalogQuery.call(workspace: @workspace, filters: criteria, public_view: !@owner_view)
        records = records.where(agent_trip_revisions: { destination: filters["destination"] }) if filters["destination"].present?
        if filters["month"].present?
          return @workspace.agent_trips.none unless filters["month"].to_s.match?(/\A\d{4}-\d{2}\z/)
          month = Date.iso8601("#{filters['month']}-01")
          records = records.where(agent_trip_revisions: { departs_on: month...month.next_month })
        end
        if (duration = DURATIONS[filters["duration"]])
          comparison = duration.first == "max_days" ? "<=" : ">="
          records = records.where("agent_trip_revisions.duration_days #{comparison} ?", duration.last.to_i)
        end
        records
      end
    rescue Date::Error
      @workspace.agent_trips.none
    end
  end
end
