module Agent
  class OnboardingController < ApplicationController
    skip_before_action :require_authentication
    skip_before_action :set_current_context
    layout "agent"

    def show
      response.headers["Cache-Control"] = "private, no-store"
      @workspace = current_user&.agent_workspace || AgentWorkspace.new
    end

    def create
      return redirect_to(agent_onboarding_path) unless current_user
      @workspace = current_user.agent_workspace
      return redirect_to(agent_onboarding_path) if @workspace
      @workspace = AgentWorkspace.new(params.expect(agent_workspace: [ :business_name, :public_name, :whatsapp, :subdomain, :presentation ]))
      @workspace.owner = current_user
      if @workspace.save
        redirect_to agent_onboarding_path, notice: "Tu web está lista. Ingresá a tu panel para cargar y publicar tu primer viaje."
      else
        render :show, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotUnique
      @workspace.errors.add(:subdomain, "ya está en uso; elegí otro")
      render :show, status: :unprocessable_entity
    end
  end
end
