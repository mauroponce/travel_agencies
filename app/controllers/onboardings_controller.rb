class OnboardingsController < ApplicationController
  skip_before_action :set_current_context

  def show
    redirect_to dashboard_path if current_user.memberships.active.exists?
  end

  def create
    company = nil
    ApplicationRecord.transaction do
      company = Company.create!(company_params)
      membership = company.memberships.create!(user: current_user)
      membership.membership_roles.create!(role: "admin")
      AuditRecorder.call(action: "company.created", auditable: company, actor: current_user, company:)
    end
    session[:membership_id] = company.memberships.find_by!(user: current_user).id
    session[:role] = "admin"
    redirect_to dashboard_path, notice: "Empresa creada. Ya podés comenzar a configurarla."
  end

  private

  def company_params
    params.expect(company: [ :name, :slug, :email, :whatsapp ])
  end
end
