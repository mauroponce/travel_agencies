class NotificationMailer < ApplicationMailer
  def event(notification)
    @notification = notification
    mail(to: notification.user.email, subject: notification.title)
  end
end
