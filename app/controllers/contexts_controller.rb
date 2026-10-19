class ContextsController < ApplicationController
  def update
    membership_id, selected_role = params[:context_key].to_s.split(":", 2)
    membership = current_user.memberships.active.find(membership_id.presence || params[:membership_id])
    role = selected_role.presence || params[:role].to_s
    raise Pundit::NotAuthorizedError unless membership.role?(role)

    session[:membership_id] = membership.id
    session[:role] = role
    redirect_to dashboard_path
  end
end
