module Agent
  class SearchesController < BaseController
    rescue_from AiRequests::Limited do |error|
      render plain: error.message, status: :too_many_requests
    end
    def index
      @searches = current_agent_workspace.agent_searches.order(created_at: :desc, id: :desc).limit(10)
      @idempotency_key = SecureRandom.uuid
    end
    def create
      search = AiRequests.create!(workspace: current_agent_workspace, kind: "search", attributes: { query: params.require(:query), idempotency_key: params.require(:idempotency_key) })
      AgentAiJob.perform_later("search", search.id) if search.status == "pending"
      redirect_to agent_search_path(search)
    end
    def show
      @search = current_agent_workspace.agent_searches.find(params[:id])
      if @search.status == "completed"
        @trips, @pagination = paginate(CatalogQuery.call(workspace: current_agent_workspace, filters: @search.filters, search: true))
      end
    end
  end
end
