class CommissionsController < ApplicationController
  before_action -> { require_role!("admin", "reseller") }

  def index
    scope = CommissionEntry.where(company: current_company).includes(:reservation, reseller_membership: :user)
    scope = scope.where(reseller_membership: current_membership) if current_role == "reseller"
    @entries = scope.order(created_at: :desc)
    @totals = @entries.reorder(nil).group(:status).sum(:amount_cents)
    @rules = CommissionRule.where(company: current_company, status: "active").includes(reseller_membership: :user)
  end
end
