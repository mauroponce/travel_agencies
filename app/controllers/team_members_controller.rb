class TeamMembersController < ApplicationController
  before_action -> { require_role!("admin") }

  def index
    @memberships, @memberships_pagination = paginate(
      current_company.memberships.includes(:user, :membership_roles, :reseller_authorization).order(created_at: :desc),
      param: :memberships_page, per_page: 20
    )
    @invitations, @invitations_pagination = paginate(
      CompanyInvitation.where(company: current_company).order(created_at: :desc),
      param: :invitations_page, per_page: 20
    )
  end

  def create
    roles = Array(params[:roles]).intersection(MembershipRole::ROLES)
    invitation, token = CompanyInvitation.issue!(company: current_company, email: params[:email], roles:, invited_by: current_user)
    CompanyInvitationMailer.invite(invitation, token).deliver_later
    redirect_to team_members_path, notice: "Invitación enviada a #{invitation.email}."
  end

  def update
    membership = current_company.memberships.find(params[:id])
    attributes = params.expect(membership: [ :status, :auto_confirm_enabled, :commercial_phone ]).to_h
    Memberships::UpdateAccess.call(membership:, attributes:)
    redirect_to team_members_path, notice: "Acceso actualizado."
  rescue Memberships::UpdateAccess::LastAdministrator => error
    redirect_to team_members_path, alert: error.message
  end
end
