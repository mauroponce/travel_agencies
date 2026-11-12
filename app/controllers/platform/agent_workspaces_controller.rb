module Platform
  class AgentWorkspacesController < ApplicationController
    before_action -> { raise Pundit::NotAuthorizedError unless current_user.platform_operator? }
    def index
      @workspaces, @pagination = paginate(AgentWorkspace.includes(:owner, :hostname_registration, :agent_subscription).order(:business_name, :id))
    end
    def new
      @workspace = AgentWorkspace.new(whatsapp: "541160347665")
    end
    def create
      attributes = params.expect(agent_workspace: [ :name, :slug, :whatsapp, :invited_email ])
      attributes[:slug] = nil if attributes[:slug].blank?
      @workspace = AgentWorkspace.new(attributes)
      if @workspace.save
        AgentWorkspaceMailer.invite(@workspace).deliver_later
        AuditRecorder.call(action: "agent_workspace.invited", auditable: @workspace)
        redirect_to platform_agent_workspaces_path, notice: "Asesor creado. Invitación enviada al correo indicado."
      else
        render :new, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      @workspace.errors.add(:base, "El correo o link público ya está en uso.")
      render :new, status: :unprocessable_entity
    end
    def update
      workspace = AgentWorkspace.find(params[:id])
      workspace.with_lock { workspace.update!(status: params.expect(agent_workspace: [ :status ])[:status]) }
      AuditRecorder.call(action: "agent_workspace.status_changed", auditable: workspace, changeset: { status: workspace.status })
      redirect_to platform_agent_workspaces_path, notice: "Estado actualizado."
    end
  end
end
