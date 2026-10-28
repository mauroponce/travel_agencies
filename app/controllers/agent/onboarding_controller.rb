module Agent
  class OnboardingController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :set_current_context
    layout "agent"

    def show
      response.headers["Cache-Control"] = "private, no-store"
      @workspace = current_user&.agent_workspace || AgentWorkspace.new(name: current_user&.name)
      @workspace.slug = AgentWorkspace.suggest_slug(@workspace.name) if current_user && @workspace.new_record?
    end

    def suggestion
      return head :unauthorized unless current_user
      response.headers["Cache-Control"] = "private, no-store"
      candidate = PlatformHosts.normalize(params[:slug])
      render json: { available: AgentWorkspace.slug_available?(candidate),
        slug: AgentWorkspace.suggest_slug(params[:name].presence || candidate) }
    end

    def create
      return redirect_to(agent_onboarding_path) unless current_user
      @workspace = current_user.agent_workspace
      return redirect_to(agent_onboarding_path) if @workspace
      @workspace = AgentWorkspace.new(params.expect(agent_workspace: [ :name, :whatsapp, :slug, :presentation ]))
      @workspace.owner = current_user
      if @workspace.save
        redirect_to agent_onboarding_path, notice: "Tu web está lista. Ingresá a tu panel para cargar y publicar tu primer viaje."
      else
        suggest_alternative
        render :show, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      return redirect_to(agent_onboarding_path) if current_user.reload.agent_workspace
      @workspace.errors.add(:slug, "ya está en uso; elegí otro o usá la sugerencia")
      suggest_alternative
      render :show, status: :unprocessable_entity
    end

    private

    def suggest_alternative
      @suggested_slug = AgentWorkspace.suggest_slug(@workspace.slug.presence || @workspace.name) if @workspace.errors[:slug].any?
    end
  end
end
