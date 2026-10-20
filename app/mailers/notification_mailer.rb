class NotificationMailer < ApplicationMailer
  def event(notification)
    @notification = notification
    path = Rails.application.routes.url_helpers.open_notification_path(notification)
    @notification_url = if notification.company
      CompanyUrl.call(notification.company, path:)
    else
      PlatformHosts.url(host: PlatformHosts.platform_host, path:)
    end
    mail(to: notification.user.email, subject: notification.title)
  end
end
