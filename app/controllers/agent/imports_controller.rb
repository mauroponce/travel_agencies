module Agent
  class ImportsController < BaseController
    before_action :set_import, only: %i[show source preview retry_processing]
    rescue_from UploadValidator::Invalid, with: :invalid_upload
    rescue_from AiRequests::Limited do |error|
      render plain: error.message, status: :too_many_requests
    end
    def index
      @imports, @pagination = paginate(current_agent_workspace.agent_imports.order(created_at: :desc, id: :desc))
      @idempotency_key = SecureRandom.uuid
    end
    def create
      file = params.require(:source)
      UploadValidator.call(file)
      digest = Digest::SHA256.file(file.tempfile.path).hexdigest
      @import = AiRequests.create!(workspace: current_agent_workspace, kind: "import", attributes: { idempotency_key: params.require(:idempotency_key), file_digest: digest, source: file })
      AgentAiJob.perform_later("import", @import.id) if @import.status == "pending"
      redirect_to agent_import_path(@import), notice: "Archivo recibido. Revisá cada ficha antes de publicar."
    end
    def show
      @duplicates = current_agent_workspace.agent_imports.where(file_digest: @import.file_digest).where.not(id: @import.id).count
    end
    def source
      raise ActiveRecord::RecordNotFound unless @import.source.attached?
      send_data @import.source.download, filename: @import.source.filename.to_s, type: @import.source.content_type, disposition: params[:download] ? "attachment" : "inline"
    end
    def preview
      raise ActiveRecord::RecordNotFound unless @import.preview.attached?
      send_data @import.preview.download, type: @import.preview.content_type, disposition: "inline"
    end
    def retry_processing
      current_agent_workspace.with_lock do
        @import.lock!
        if @import.status == "error"
          # A new explicit request is rate limited too. Keep the source/candidates and the request identity.
          recent = current_agent_workspace.agent_ai_executions.where.not(agent_import_id: nil).where("created_at > ?", 1.minute.ago).count
          raise AiRequests::Limited, "Esperá un minuto antes de reintentar." if recent >= ENV.fetch("AGENT_IMPORTS_PER_MINUTE", 5).to_i
          @import.update!(status: "pending", error_code: nil, attempts: 0, processing_token: nil)
        end
      end
      AgentAiJob.perform_later("import", @import.id) if @import.status == "pending"
      redirect_to agent_import_path(@import)
    end
    private
    def set_import = @import = current_agent_workspace.agent_imports.find(params[:id])
    def invalid_upload(error) = render(plain: error.message, status: :unprocessable_entity)
  end
end
