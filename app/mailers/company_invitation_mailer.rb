class CompanyInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @token = token
    mail(to: invitation.email, subject: "Te invitaron a #{invitation.company.name} en NexoViajes")
  end
end
