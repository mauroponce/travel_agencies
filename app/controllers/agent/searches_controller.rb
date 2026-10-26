module Agent
  class SearchesController < BaseController
    def index
      @searches = current_agent_workspace.agent_searches.order(created_at: :desc, id: :desc).limit(10)
      @idempotency_key = SecureRandom.uuid
    end
    def create
      search = AiRequests.create!(workspace: current_agent_workspace, kind: "search", attributes: { query: params.require(:query), idempotency_key: params.require(:idempotency_key) })
      AgentAiJob.perform_later("search", search.id) if search.status == "pending"
      redirect_to agent_search_path(search)
    rescue AiRequests::Limited, ActiveRecord::RecordInvalid => error
      index
      @form_error = form_error_message(error)
      @idempotency_key = params[:idempotency_key].presence || SecureRandom.uuid
      render :index, status: error.is_a?(AiRequests::Limited) ? :too_many_requests : :unprocessable_entity
    end
    def show
      @search = current_agent_workspace.agent_searches.find(params[:id])
      if @search.status == "completed"
        @trips, @pagination = paginate(CatalogQuery.call(workspace: current_agent_workspace, filters: @search.filters, search: true))
      end
    end
  end
end
