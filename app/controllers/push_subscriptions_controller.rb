class PushSubscriptionsController < ApplicationController
  protect_from_forgery with: :exception

  def create
    subscription = current_user.push_subscriptions.find_or_initialize_by(endpoint: subscription_params[:endpoint])
    subscription.update!(subscription_params.merge(user_agent: request.user_agent, last_used_at: Time.current))
    head :created
  end

  def destroy
    current_user.push_subscriptions.find(params[:id]).destroy!
    head :no_content
  end

  private

  def subscription_params = params.expect(push_subscription: [ :endpoint, :p256dh, :auth ])
end
