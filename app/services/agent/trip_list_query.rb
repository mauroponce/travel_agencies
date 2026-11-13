module Agent
  # The private table has its own grouping, search and order. Public catalog
  # queries continue to use published revisions and departure order.
  class TripListQuery
    FILTERS = (CatalogQuery::FILTERS - %w[status sort]).freeze
    TABS = {
      "published" => { label: "Publicados", statuses: %w[published] },
      "drafts" => { label: "Borradores", statuses: %w[draft unpublished] },
      "archived" => { label: "Archivados", statuses: %w[archived] }
    }.freeze

    attr_reader :tab, :filters

    def self.normalize_tab(value)
      TABS.key?(value) ? value : "published"
    end

    def initialize(workspace:, filters: {}, tab: nil)
      @workspace = workspace
      @filters = filters.to_h.stringify_keys.slice(*FILTERS).reject { |_key, value| value.blank? }
      @tab = self.class.normalize_tab(tab)
    end

    def trips
      scope.where(status: TABS.fetch(tab).fetch(:statuses))
    end

    def counts
      grouped = scope.except(:includes, :order).group("agent_trips.status").count
      TABS.transform_values { |config| config.fetch(:statuses).sum { |status| grouped.fetch(status, 0) } }
    end

    private

    def scope
      @scope ||= begin
        records = CatalogQuery.call(workspace: @workspace, filters: filters.except("q"))
          .joins(current_revision: :agent_supplier)
        if filters["q"].present?
          term = "%#{AgentTrip.sanitize_sql_like(filters["q"].to_s.first(200))}%"
          records = records.where("unaccent(agent_trip_revisions.title) ILIKE unaccent(:q) OR unaccent(agent_trip_revisions.destination) ILIKE unaccent(:q) OR unaccent(agent_suppliers.name) ILIKE unaccent(:q)", q: term)
        end
        records.reorder(created_at: :desc, id: :desc)
      end
    end
  end
end
