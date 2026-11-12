class AddAgentProSubscriptions < ActiveRecord::Migration[8.1]
  def up
    create_table :agent_subscriptions, id: :uuid do |t|
      t.references :agent_workspace, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "trialing"
      t.string :origin, null: false, default: "signup"
      t.integer :price_cents, null: false, default: 1900
      t.string :currency, null: false, default: "USD"
      t.datetime :trial_starts_at, null: false
      t.datetime :trial_ends_at, null: false
      t.datetime :current_period_starts_at
      t.datetime :current_period_ends_at
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.datetime :activation_requested_at
      t.timestamps
    end
    add_check_constraint :agent_subscriptions, "status IN ('trialing', 'active', 'inactive')", name: "agent_subscription_status"
    add_check_constraint :agent_subscriptions, "price_cents >= 0 AND currency = 'USD'", name: "agent_subscription_price"
    add_check_constraint :agent_subscriptions, "trial_ends_at > trial_starts_at", name: "agent_subscription_trial_dates"
    add_check_constraint :agent_subscriptions, "(current_period_starts_at IS NULL AND current_period_ends_at IS NULL) OR (current_period_starts_at IS NOT NULL AND current_period_ends_at > current_period_starts_at)", name: "agent_subscription_period_dates"
    transition_pilots!
  end

  def transition_pilots!
    # A bounded, one-time transition. Never restarts on deploy, onboarding or login.
    days = Integer(ENV.fetch("AGENT_PILOT_TRANSITION_DAYS", "30")).clamp(1, 90)
    price = Integer(ENV.fetch("AGENT_PRO_PRICE_CENTS", "1900"))
    execute <<~SQL
      INSERT INTO agent_subscriptions
        (id, agent_workspace_id, status, origin, price_cents, currency, trial_starts_at, trial_ends_at, created_at, updated_at)
      SELECT gen_random_uuid(), id, 'trialing', 'pilot_transition', #{price}, 'USD',
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '#{days} days', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM agent_workspaces
      ON CONFLICT (agent_workspace_id) DO NOTHING
    SQL
  end

  def down
    drop_table :agent_subscriptions
  end
end
