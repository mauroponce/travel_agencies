module Platform
  class CompaniesController < ApplicationController
    before_action :require_operator

    def index
      @companies = Company.order(:name)
    end

    def new
      @company = Company.new
    end

    def create
      company = nil
      invitation = nil
      token = nil
      ApplicationRecord.transaction do
        company = Company.create!(company_params)
        invitation, token = CompanyInvitation.issue!(company:, email: params[:admin_email], roles: [ "admin" ], invited_by: current_user)
      end
      CompanyInvitationMailer.invite(invitation, token).deliver_later
      redirect_to platform_companies_path, notice: "Empresa creada e invitación enviada."
    end

    private

    def require_operator
      raise Pundit::NotAuthorizedError unless current_user.platform_operator?
    end

    def company_params = params.expect(company: [ :name, :slug, :email, :whatsapp ])
  end
end
