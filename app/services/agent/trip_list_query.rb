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
      legacy_destination = @filters.delete("q")
      @filters["destination"] ||= legacy_destination if legacy_destination.present?
      @tab = self.class.normalize_tab(tab)
    end

    def trips
      scope.where(status: TABS.fetch(tab).fetch(:statuses))
    end

    def counts
      grouped = scope.except(:includes, :order).group("agent_trips.status").count
      TABS.transform_values { |config| config.fetch(:statuses).sum { |status| grouped.fetch(status, 0) } }
    end

    def destinations
      trips.except(:includes, :order)
        .where.not(agent_trip_revisions: { destination: [ nil, "" ] })
        .distinct.order("agent_trip_revisions.destination").limit(10)
        .pluck("agent_trip_revisions.destination")
    end

    private

    def scope
      @scope ||= CatalogQuery.call(workspace: @workspace, filters:).reorder(created_at: :desc, id: :desc)
    end
  end
end
