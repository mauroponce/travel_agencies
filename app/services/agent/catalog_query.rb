module Agent
  class CatalogQuery
    FILTERS = %w[q supplier_id status destination region from to min_price max_price currency price_unit meal_plan transport departure_location min_days max_days sort].freeze
    def self.call(workspace:, filters: {}, public_view: false, search: false)
      filters = filters.to_h.stringify_keys.slice(*FILTERS)
      revision = public_view ? :published_revision : :current_revision
      scope = workspace.agent_trips
      scope = scope.publicly_visible if public_view
      scope = scope.joins(revision).includes(revision => [ :agent_supplier, { cover_attachment: :blob } ])
      table = "agent_trip_revisions"
      if search
        scope = scope.where.not(status: "archived").where("#{table}.departs_on >= ?", Date.current)
          .where(table => { agent_supplier_id: workspace.agent_suppliers.active.select(:id) })
      end
      if filters["q"].present?
        term = "%#{AgentTrip.sanitize_sql_like(filters["q"].to_s.first(200))}%"
        scope = scope.where("unaccent(#{table}.title) ILIKE unaccent(:q) OR unaccent(#{table}.destination) ILIKE unaccent(:q)", q: term)
      end
      %w[destination region meal_plan transport departure_location].each do |field|
        next if filters[field].blank?
        scope = scope.where("unaccent(#{table}.#{field}) ILIKE unaccent(?)", "%#{AgentTrip.sanitize_sql_like(filters[field].to_s.first(200))}%")
      end
      scope = scope.where(table => { agent_supplier_id: filters["supplier_id"] }) if filters["supplier_id"].present?
      unless public_view
        case filters["status"]
        when "expired" then scope = scope.where("#{table}.departs_on < ?", Date.current)
        when *%w[draft published unpublished archived] then scope = scope.where(status: filters["status"])
        end
      end
      %w[from to].each do |key|
        next if filters[key].blank?
        date = Date.iso8601(filters[key].to_s)
        scope = scope.where("#{table}.departs_on #{key == 'from' ? '>=' : '<='} ?", date)
      end
      %w[currency price_unit].each { |field| scope = scope.where(table => { field => filters[field] }) if filters[field].present? }
      if filters["min_price"].present? || filters["max_price"].present?
        # A price comparison without a currency and unit has no defined meaning.
        return scope.none if filters["currency"].blank? || filters["price_unit"].blank?
        %w[min_price max_price].each do |field|
          next if filters[field].blank?
          cents = MoneyParser.call(filters[field])
          scope = scope.where("#{table}.price_cents #{field == 'min_price' ? '>=' : '<='} ?", cents)
        end
      end
      %w[min_days max_days].each do |field|
        next if filters[field].blank?
        scope = scope.where("#{table}.duration_days #{field == 'min_days' ? '>=' : '<='} ?", Integer(filters[field]))
      end
      sort = if %w[price_asc price_desc].include?(filters["sort"]) && filters["currency"].present? && filters["price_unit"].present?
        "#{table}.price_cents #{filters['sort'] == 'price_desc' ? 'DESC' : 'ASC'} NULLS LAST, agent_trips.id ASC"
      else
        "#{table}.departs_on ASC NULLS LAST, agent_trips.id ASC"
      end
      scope.order(Arel.sql(sort))
    rescue Date::Error, ArgumentError, MoneyParser::InvalidAmount
      workspace.agent_trips.none
    end
  end
end
