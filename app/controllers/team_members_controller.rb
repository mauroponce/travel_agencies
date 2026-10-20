class TeamMembersController < ApplicationController
  before_action -> { require_role!("admin") }

  def index
    @memberships = current_company.memberships.includes(:user, :membership_roles, :reseller_authorization).order(created_at: :desc)
    @invitations = CompanyInvitation.where(company: current_company).order(created_at: :desc).limit(20)
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
    ApplicationRecord.transaction do
      membership.update!(status: attributes[:status]) if attributes[:status].present?
      membership.update!(commercial_phone: attributes[:commercial_phone]) if attributes.key?(:commercial_phone)
      if membership.reseller_authorization && attributes.key?(:auto_confirm_enabled)
        membership.reseller_authorization.update!(auto_confirm_enabled: attributes[:auto_confirm_enabled] == "1")
      end
    end
    redirect_to team_members_path, notice: "Acceso actualizado."
  end
end
