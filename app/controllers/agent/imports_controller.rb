module Agent
  class ImportsController < BaseController
    before_action :set_import, only: %i[show source preview retry_processing]
    def index
      @imports, @pagination = paginate(current_agent_workspace.agent_imports.order(created_at: :desc, id: :desc))
      @idempotency_key = SecureRandom.uuid
    end
    def create
      file = retain_cover(params[:source])
      raise UploadValidator::Invalid, "Seleccioná un archivo JPG, PNG, WebP o PDF." unless file
      digest = file.open { |io| Digest::SHA256.file(io.path).hexdigest }
      @import = AiRequests.create!(workspace: current_agent_workspace, kind: "import", attributes: { idempotency_key: params.require(:idempotency_key), file_digest: digest, source: file })
      AgentAiJob.perform_later("import", @import.id) if @import.status == "pending"
      redirect_to agent_import_path(@import), notice: "Archivo recibido. Revisá cada ficha antes de publicar."
    rescue UploadValidator::Invalid, AiRequests::Limited, ActiveRecord::RecordInvalid => error
      index
      @form_error = form_error_message(error)
      @idempotency_key = params[:idempotency_key].presence || SecureRandom.uuid
      render :index, status: error.is_a?(AiRequests::Limited) ? :too_many_requests : :unprocessable_entity
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
      AiRequests.retry_import!(@import)
      AgentAiJob.perform_later("import", @import.id) if @import.status == "pending"
      redirect_to agent_import_path(@import)
    rescue AiRequests::Limited => error
      redirect_to agent_import_path(@import), alert: error.message
    end
    private
    def set_import = @import = current_agent_workspace.agent_imports.find(params[:id])
  end
end
