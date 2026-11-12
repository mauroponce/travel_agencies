# Loaded only by the explicitly enabled browser fixture initializer/routes.
class E2eProLifecycleController < ApplicationController
  skip_before_action :enforce_host_scope
  skip_before_action :set_current_context
  skip_before_action :require_authentication, only: :prepare

  def prepare
    raise ActionController::RoutingError, "Not Found" unless Rails.env.test? && ENV["AGENT_E2E_FIXTURES"] == "true" && Current.host_scope == "auth"
    token = SecureRandom.hex(8)
    user = User.create!(google_sub: "pilot-#{token}", email: "pilot-#{token}@example.test", name: "Asesor del piloto")
    second_company = Company.find_or_create_by!(slug: "pilot-fixture-company") { |record| record.name = "Segunda empresa del piloto" }
    Company.where(id: [ Company.find_by!(slug: "sanzo-viajes").id, second_company.id ]).each do |company|
      membership = user.memberships.create!(company:, status: "active")
      membership.membership_roles.create!(role: "coordinator")
    end
    operator = User.find_or_create_by!(email: "e2e-operator@example.test") { |record| record.assign_attributes(name: "Operador E2E", google_sub: "e2e-operator") }
    operator.platform_roles.find_or_create_by!(role: "operator")
    session[:e2e_google_user_id] = user.id
    render json: { email: user.email, operator_email: operator.email }
  end

  def show
    workspace = current_user.agent_workspace
    subscription = workspace.agent_subscription
    render json: { workspace_id: workspace.id, trial_seconds: subscription.trial_ends_at - subscription.trial_starts_at,
      status: subscription.entitled? ? subscription.status : "expired", price_cents: subscription.price_cents,
      memberships: current_user.memberships.order(:id).map { |membership| membership.attributes.merge("roles" => membership.membership_roles.order(:role).pluck(:role)) } }
  end

  def expire
    current_user.agent_workspace.with_lock do
      current_user.agent_workspace.agent_subscription.update!(trial_starts_at: 30.days.ago, trial_ends_at: 16.days.ago)
    end
    head :no_content
  end
end
