class LandingController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context

  def show
    if Current.host_scope == "platform"
      return redirect_to platform_companies_path if current_user&.platform_operator?
      return redirect_to context_path if current_user
      render :pro
    elsif current_user&.memberships&.active&.exists?(company: current_company)
      redirect_to dashboard_path
    end
  end
end
