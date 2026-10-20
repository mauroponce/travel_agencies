class ContextsController < ApplicationController
  def update
    role = params[:role].to_s
    raise Pundit::NotAuthorizedError unless current_membership.role?(role)

    session[:role] = role
    redirect_to dashboard_path
  end
end
