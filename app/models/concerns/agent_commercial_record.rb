module AgentCommercialRecord
  extend ActiveSupport::Concern

  included do
    around_save :with_commercial_access
    around_destroy :with_commercial_access
  end

  private

  def with_commercial_access
    agent_workspace.with_lock do
      Agent::Access.new(agent_workspace).require_commercial!
      yield
    end
  end
end
