class CommissionsController < ApplicationController
  before_action -> { require_role!("admin", "reseller") }

  def index
    scope = CommissionEntry.where(company: current_company).includes(:reservation, reseller_membership: :user)
    scope = scope.where(reseller_membership: current_membership) if current_role == "reseller"
    @totals = scope.reorder(nil).group(:status).sum(:amount_cents)
    @entries, @entries_pagination = paginate(scope.order(created_at: :desc), per_page: 25)
    rules = CommissionRule.where(company: current_company, status: "active")
    rules = rules.where(reseller_membership: current_membership) if current_role == "reseller"
    @rules = rules.includes(reseller_membership: :user)
  end
end
