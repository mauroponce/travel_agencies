class NotificationsController < ApplicationController
  def index
    @notifications = current_user.notifications.where(company: [ current_company, nil ]).order(created_at: :desc).limit(100)
  end

  def update
    notification = current_user.notifications.find(params[:id])
    notification.update!(read_at: Time.current)
    redirect_to notifications_path
  end

  def read_all
    current_user.notifications.where(company: [ current_company, nil ], read_at: nil).update_all(read_at: Time.current, updated_at: Time.current)
    redirect_to notifications_path, notice: "Notificaciones marcadas como leídas."
  end
end
