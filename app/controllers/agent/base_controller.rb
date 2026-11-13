module Agent
  class BaseController < ApplicationController
    before_action :authorize_workspace
    before_action :authorize_commercial_write
    helper_method :agent_access
    layout "agent"
    rescue_from ActiveRecord::RecordInvalid, with: :invalid_record
    rescue_from Agent::UploadValidator::Invalid, ::MoneyParser::InvalidAmount do |error|
      render_agent_error(error.message)
    end
    rescue_from ActiveRecord::RecordNotUnique do
      render_agent_error("El nombre ya está registrado en tu cuenta. Usá el proveedor existente o elegí otro nombre.")
    end
    rescue_from ActiveRecord::StaleObjectError do
      render_agent_error("La ficha cambió en otra ventana. Revisá la versión actual antes de guardar.", status: :conflict)
    end

    private

    def authorize_workspace
      authorize current_agent_workspace, :access?, policy_class: AgentWorkspacePolicy
      response.headers["Cache-Control"] = "private, no-store"
    end

    def agent_access = Agent::Access.new(current_agent_workspace)

    def authorize_commercial_write
      agent_access.require_commercial! unless (request.get? || request.head?) && !%w[new edit preview].include?(action_name)
    end

    def pundit_user = Current

    def invalid_record(error)
      render_agent_error(error.record.errors.full_messages.to_sentence)
    end

    def render_agent_error(message, status: :unprocessable_entity)
      @error_message = message
      render "agent/error", status:
    end

    def form_error_message(error)
      case error
      when ActiveRecord::RecordInvalid then error.record.errors.full_messages.to_sentence
      when ActiveRecord::RecordNotUnique then "El proveedor ya está registrado. Seleccionalo en la lista o elegí otro nombre."
      when ActiveRecord::StaleObjectError then "La ficha cambió en otra ventana. Tus datos siguen abajo; abrí la versión actual antes de volver a guardar."
      else error.message
      end
    end

    # Unattached blobs have no public routes. Bind the form token to its workspace
    # so a validation failure can retain a flyer without granting cross-tenant access.
    def retain_cover(upload = nil)
      token = params[:retained_cover].presence
      @retained_cover = ActiveStorage::Blob.find_signed!(token, purpose: cover_purpose) if token
      if upload.present?
        mime = UploadValidator.call(upload)
        @retained_cover = ActiveStorage::Blob.create_and_upload!(io: upload.tempfile, filename: upload.original_filename, content_type: mime)
      end
      @retained_cover
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise ActiveRecord::RecordNotFound
    end

    def retained_cover_token
      @retained_cover&.signed_id(purpose: cover_purpose, expires_in: 2.days)
    end
    helper_method :retained_cover_token

    def cover_purpose = "agent-cover:#{current_agent_workspace.id}"

    def audit(action, record)
      AuditRecorder.call(action:, auditable: record, changeset: {})
    end
  end
end
