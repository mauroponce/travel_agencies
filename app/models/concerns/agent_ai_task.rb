module AgentAiTask
  extend ActiveSupport::Concern
  included do
    belongs_to :agent_workspace
    validates :idempotency_key, presence: true, uniqueness: { scope: :agent_workspace_id }
    validates :status, inclusion: { in: %w[pending processing completed error] }
  end
end
