class CompanyInvitationMailer < ApplicationMailer
  def invite(invitation, token)
    @invitation = invitation
    @token = token
    @login_url = CompanyUrl.call(invitation.company)
    mail(to: invitation.email, subject: "Te invitaron a #{invitation.company.name}")
  end
end
