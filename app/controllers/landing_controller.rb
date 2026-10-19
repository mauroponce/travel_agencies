class LandingController < ApplicationController
  skip_before_action :require_authentication
  skip_before_action :set_current_context

  def show
    redirect_to dashboard_path if current_user&.memberships&.active&.exists?
  end
end
