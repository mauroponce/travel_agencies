module Agent
  class Subscriptions
    # No payment processor. Each grant explicitly adds one calendar month.
    def self.grant_month!(workspace:, actor:)
      raise Pundit::NotAuthorizedError unless actor&.platform_operator?
      workspace.with_lock do
        subscription = workspace.agent_subscription
        start = subscription.status == "active" && subscription.current_period_ends_at&.future? ? subscription.current_period_ends_at : Time.current
        subscription.update!(status: "active", current_period_starts_at: subscription.status == "active" && subscription.entitled? ? subscription.current_period_starts_at : start,
          current_period_ends_at: start.advance(months: 1), cancel_at_period_end: false, canceled_at: nil, activation_requested_at: nil)
        AuditRecorder.call(action: "agent_subscription.month_granted", auditable: subscription, actor:, company: nil,
          changeset: subscription.attributes.slice("status", "current_period_starts_at", "current_period_ends_at", "price_cents", "currency"))
      end
    end

    def self.cancel!(workspace:)
      workspace.with_lock do
        subscription = workspace.agent_subscription
        subscription.update!(cancel_at_period_end: true, canceled_at: subscription.canceled_at || Time.current)
        AuditRecorder.call(action: "agent_subscription.cancel_at_period_end", auditable: subscription, company: nil)
      end
    end
  end
end
