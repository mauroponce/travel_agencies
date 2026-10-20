class ScopePushSubscriptionsToTenants < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :push_subscriptions,
      "(company_id IS NULL AND origin_hostname IS NULL) OR (company_id IS NOT NULL AND origin_hostname IS NOT NULL)",
      name: "push_subscriptions_tenant_scope_consistent"
  end
end
