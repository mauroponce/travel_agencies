class OnboardingsController < ApplicationController
  skip_before_action :set_current_context

  def show
    redirect_to root_path, alert: "Las agencias se habilitan únicamente por invitación de la plataforma."
  end
end
