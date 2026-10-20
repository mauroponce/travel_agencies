class DeliverNotificationJob < ApplicationJob
  queue_as :notifications

  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(notification_id)
    notification = Notification.find(notification_id)
    return if notification.company && (notification.company.status != "active" ||
      !notification.company.memberships.active.exists?(user: notification.user))

    NotificationMailer.event(notification).deliver_later if email_enabled?(notification)
    notification.user.push_subscriptions.where(company: notification.company).find_each do |subscription|
      deliver_push(notification, subscription)
    end if push_enabled?(notification)
  end

  private

  def email_enabled?(notification)
    membership = notification.company&.memberships&.find_by(user: notification.user)
    preference = membership&.notification_preferences&.find_by(event_type: notification.event_type)
    preference.nil? || preference.email?
  end

  def deliver_push(notification, subscription)
    domain = notification.company.company_domains.active.find_by(hostname: subscription.origin_hostname)
    return unless domain
    action_url = PlatformHosts.url(host: domain.hostname,
      path: Rails.application.routes.url_helpers.open_notification_path(notification))
    WebPush.payload_send(endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
      message: { title: notification.title, body: notification.body, url: action_url }.to_json,
      vapid: { subject: ENV.fetch("VAPID_SUBJECT", "mailto:soporte@localhost"),
              public_key: ENV.fetch("VAPID_PUBLIC_KEY"), private_key: ENV.fetch("VAPID_PRIVATE_KEY") })
    subscription.touch(:last_used_at)
  rescue WebPush::InvalidSubscription, WebPush::ExpiredSubscription
    subscription.destroy!
  end

  def push_enabled?(notification)
    return false unless notification.company
    return false unless ENV["VAPID_PUBLIC_KEY"].present? && ENV["VAPID_PRIVATE_KEY"].present?
    membership = notification.company&.memberships&.find_by(user: notification.user)
    preference = membership&.notification_preferences&.find_by(event_type: notification.event_type)
    preference.nil? || preference.web_push?
  end
end
