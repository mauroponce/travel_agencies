module Agent
  class TripImportsController < BaseController
    before_action :set_import, only: %i[show source preview retry_processing review confirm supplier]
    def index
      imports = current_agent_workspace.agent_imports.order(created_at: :desc, id: :desc).limit(10)
      render json: { imports: imports.map { |item| { id: item.id, filename: item.source.filename.to_s, status: item.status, url: agent_trip_import_path(item, format: :json) } } }
    end
    def create
      file = retain_cover(params[:source])
      raise UploadValidator::Invalid, "Seleccioná un archivo JPG, PNG, WebP o PDF." unless file
      digest = file.open { |io| Digest::SHA256.file(io.path).hexdigest }
      @import = AiRequests.create!(workspace: current_agent_workspace, kind: "import", attributes: { idempotency_key: params.require(:idempotency_key), file_digest: digest, source: file })
      AgentAiJob.perform_later("import", @import.id) if @import.status == "pending"
      render_import
    rescue UploadValidator::Invalid, AiRequests::Limited, ActiveRecord::RecordInvalid => error
      status = error.is_a?(AiRequests::Limited) ? :too_many_requests : :unprocessable_entity
      render json: { error: form_error_message(error), retained_cover: retained_cover_token }, status:
    end
    def show = render_import
    def review
      ImportReview.new(@import).save!(review_rows)
      render_import
    rescue ImportReview::Invalid, ActiveRecord::RecordInvalid, ::MoneyParser::InvalidAmount => error
      render json: { error: form_error_message(error) }, status: :unprocessable_entity
    end
    def confirm
      # Keep human corrections even if the all-or-nothing creation fails.
      ImportReview.new(@import).save!(review_rows) if params.key?(:items)
      trips = SaveImport.call(import: @import, acknowledge_duplicates: params[:acknowledge_duplicates] == true || params[:acknowledge_duplicates] == "true")
      render json: { trips: trips.map { |trip| { id: trip.id, title: trip.current_revision.title, departs_on: trip.current_revision.departs_on, url: agent_trip_path(trip) } },
        redirect_url: agent_trips_path(tab: "drafts"), count: trips.size }
    rescue ImportReview::Invalid, ActiveRecord::RecordInvalid, ::MoneyParser::InvalidAmount, UploadValidator::Invalid => error
      render json: { error: form_error_message(error) }, status: :unprocessable_entity
    end
    def supplier
      supplier = SupplierMatch.find_or_create!(workspace: current_agent_workspace, name: params.require(:name))
      render json: { supplier: { id: supplier.id, name: supplier.name, status: supplier.status } }
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
      render json: { error: form_error_message(error) }, status: :unprocessable_entity
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
      render_import
    rescue AiRequests::Limited => error
      render json: { error: error.message }, status: :too_many_requests
    end
    private
    def set_import = @import = current_agent_workspace.agent_imports.find(params[:id])
    def review_rows
      params.permit(items: [ :id, :template_id, :client_key, :selected, { values: ImportReview::PERMITTED_FIELDS, overrides: [] } ]).to_h.fetch("items", [])
    end
    def render_import
      render json: { id: @import.id, status: @import.status, filename: @import.source.filename.to_s,
        error: @import.error_code && helpers.agent_ai_error(@import.error_code),
        source_url: source_agent_trip_import_path(@import), preview_url: @import.preview.attached? ? preview_agent_trip_import_path(@import) : nil,
        mime: @import.source.content_type, today: Time.current.in_time_zone(current_agent_workspace.timezone).to_date,
        duplicate_files: current_agent_workspace.agent_imports.where(file_digest: @import.file_digest).where.not(id: @import.id).count,
        items: @import.status == "completed" ? ImportReview.new(@import).payload : [],
        suppliers: current_agent_workspace.agent_suppliers.order(:name, :id).map { |entry| { id: entry.id, name: entry.name, status: entry.status } },
        urls: { show: agent_trip_import_path(@import, format: :json), review: review_agent_trip_import_path(@import), confirm: confirm_agent_trip_import_path(@import),
          supplier: supplier_agent_trip_import_path(@import), retry: retry_agent_trip_import_path(@import) } }
    end
  end
end
