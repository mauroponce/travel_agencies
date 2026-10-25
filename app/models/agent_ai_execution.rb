class AgentAiExecution < ApplicationRecord
  belongs_to :agent_workspace
  belongs_to :agent_import, optional: true
  belongs_to :agent_search, optional: true
end
