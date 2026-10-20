module Platform
  class CompaniesController < ApplicationController
    before_action :require_operator
    before_action :set_company, only: :update

    def index
      @companies, @companies_pagination = paginate(
        Company.includes(:memberships, :company_domains).order(:name), per_page: 20
      )
    end

    def new
      @company = Company.new
    end

    def create
      company = nil
      invitation = nil
      token = nil
      ApplicationRecord.transaction do
        company = Company.create!(company_params.merge(platform_subdomain: params[:platform_subdomain]))
        invitation, token = CompanyInvitation.issue!(company:, email: params[:admin_email], roles: [ "admin" ], invited_by: current_user)
      end
      CompanyInvitationMailer.invite(invitation, token).deliver_later
      redirect_to platform_companies_path, notice: "Empresa creada e invitación enviada."
    end

    def update
      @company.with_lock { @company.update!(status: params.expect(company: [ :status ])[:status]) }
      AuditRecorder.call(action: "company.status_changed", auditable: @company, actor: current_user,
        company: @company, changeset: { status: @company.status })
      redirect_to platform_companies_path, notice: "Estado de empresa actualizado."
    end

    private

    def require_operator
      raise Pundit::NotAuthorizedError unless current_user.platform_operator?
    end

    def set_company = @company = Company.find(params[:id])

    def company_params = params.expect(company: [ :name, :slug, :email, :whatsapp ])
  end
end
