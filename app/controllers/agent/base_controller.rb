module Agent
  class BaseController < ApplicationController
    before_action :authorize_workspace
    layout "agent"
    rescue_from ActiveRecord::RecordInvalid, with: :invalid_record
    rescue_from Agent::UploadValidator::Invalid, MoneyParser::InvalidAmount do |error|
      render plain: error.message, status: :unprocessable_entity
    end
    rescue_from ActiveRecord::RecordNotUnique do
      render plain: "El nombre ya está registrado en tu cuenta. Usá la empresa existente o elegí otro nombre.", status: :unprocessable_entity
    end
    rescue_from ActiveRecord::StaleObjectError do
      render plain: "La ficha cambió en otra ventana. Recargá antes de guardar.", status: :conflict
    end

    private

    def authorize_workspace
      authorize current_agent_workspace, :access?, policy_class: AgentWorkspacePolicy
      response.headers["Cache-Control"] = "private, no-store"
    end

    def pundit_user = Current

    def invalid_record(error)
      render plain: error.record.errors.full_messages.to_sentence, status: :unprocessable_entity
    end

    def audit(action, record)
      AuditRecorder.call(action:, auditable: record, changeset: {})
    end
  end
end
