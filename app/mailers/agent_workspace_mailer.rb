class AgentWorkspaceMailer < ApplicationMailer
  def invite(workspace)
    @workspace = workspace
    @login_url = workspace.url
    mail(to: workspace.invited_email, subject: "Tu cuenta Turistack Revendedor está lista")
  end
end
