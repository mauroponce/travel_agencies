require "test_helper"
require_relative "../support_agent_data"

class AgentSubscriptionTest < ActiveSupport::TestCase
  include AgentTestData

  test "trial dates grant exactly one bounded trial and cancellation retains access until the end" do
    workspace = agent_workspace
    subscription = workspace.agent_subscription
    assert_equal 14.days, subscription.trial_ends_at - subscription.trial_starts_at
    assert subscription.entitled?(at: subscription.trial_starts_at)
    assert_not subscription.entitled?(at: subscription.trial_ends_at)
    assert_not subscription.entitled?(at: subscription.trial_starts_at - 1.second)
    Agent::Subscriptions.cancel!(workspace:)
    assert subscription.reload.entitled?
    assert_not subscription.entitled?(at: subscription.trial_ends_at)
    Agent::Subscriptions.grant_month!(workspace:, actor: create_platform_operator)
    assert_not subscription.reload.cancel_at_period_end
    Agent::Subscriptions.cancel!(workspace:)
    assert subscription.reload.entitled?(at: subscription.current_period_ends_at - 1.second)
    assert_not subscription.entitled?(at: subscription.current_period_ends_at)
  end

  test "database rejects a note associated with a client or trip in another workspace" do
    workspace = agent_workspace
    other = agent_workspace
    client = workspace.agent_clients.create!(name: "Cliente", phone: "5491155550000")
    trip = agent_trip(workspace: other)
    note = { id: SecureRandom.uuid, agent_workspace_id: workspace.id, agent_client_id: client.id, agent_trip_id: trip.id, body: "Privado", created_at: Time.current, updated_at: Time.current }
    assert_raises(ActiveRecord::InvalidForeignKey) do
      AgentClientNote.transaction(requires_new: true) { AgentClientNote.insert_all!([ note ]) }
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      AgentClientNote.transaction(requires_new: true) { AgentClientNote.insert_all!([ note.merge(agent_workspace_id: other.id, agent_trip_id: nil) ]) }
    end
  end
  test "pilot migration gives a finite idempotent transition and preserves suspended workspaces and data" do
    require Rails.root.join("db/migrate/20261112120000_add_agent_pro_subscriptions")
    workspace = agent_workspace
    trip = agent_trip(workspace:)
    workspace.update!(status: "suspended")
    workspace.agent_subscription.delete
    migration = AddAgentProSubscriptions.new
    migration.suppress_messages { migration.transition_pilots! }
    subscription = AgentSubscription.find_by!(agent_workspace: workspace)
    original_end = subscription.trial_ends_at
    assert_equal "pilot_transition", subscription.origin
    assert_equal "trialing", subscription.status
    assert_in_delta 30.days, subscription.trial_ends_at - subscription.trial_starts_at, 1
    migration.suppress_messages { migration.transition_pilots! }
    assert_equal original_end, subscription.reload.trial_ends_at
    assert_equal "suspended", workspace.reload.status
    assert_equal trip.id, workspace.agent_trips.sole.id
    assert_equal trip.current_revision_id, trip.reload.current_revision_id
    assert_not Agent::Access.new(workspace).commercial?
  end
end
