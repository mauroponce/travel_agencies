class NotificationsController < ApplicationController
  def index
    @notifications, @notifications_pagination = paginate(
      current_user.notifications.where(company: [ current_company, nil ]).order(created_at: :desc), per_page: 30
    )
  end

  def update
    notification = current_user.notifications.where(company: [ current_company, nil ]).find(params[:id])
    notification.update!(read_at: Time.current)
    redirect_to notifications_path
  end

  def read_all
    current_user.notifications.where(company: [ current_company, nil ], read_at: nil).update_all(read_at: Time.current, updated_at: Time.current)
    redirect_to notifications_path, notice: "Notificaciones marcadas como leídas."
  end

  def open
    notification = current_user.notifications.where(company: [ current_company, nil ]).find(params[:id])
    notification.update!(read_at: Time.current) unless notification.read_at
    redirect_to safe_action_path(notification.action_url)
  end

  private

  def safe_action_path(action_url)
    path = action_url.to_s
    path.start_with?("/") && !path.start_with?("//") ? path : notifications_path
  end
end
