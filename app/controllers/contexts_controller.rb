class ContextsController < ApplicationController
  skip_before_action :set_current_context
  layout "agent"

  def show
    response.headers["Cache-Control"] = "private, no-store"
    @workspace = current_user.agent_workspace if AgentWorkspace.enabled?
    @memberships = current_user.memberships.active.joins(:company).where(companies: { status: "active" }).includes(:company)
  end

  def update
    if params[:membership_id].present?
      membership = current_user.memberships.active.find(params[:membership_id])
      raise Pundit::NotAuthorizedError unless membership.active? && membership.company.primary_domain
      # The destination host revalidates its own session/membership. If it has no
      # session, its Google entry uses the existing nonce-bound host exchange.
      return redirect_to CompanyUrl.call(membership.company), allow_other_host: true
    end
    role = params[:role].to_s
    membership = current_user.memberships.active.find_by(company: current_company)
    raise Pundit::NotAuthorizedError unless membership&.role?(role)

    session[:role] = role
    redirect_to dashboard_path
  end
end
