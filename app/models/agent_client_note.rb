class AgentClientNote < ApplicationRecord
  include AgentCommercialRecord
  belongs_to :agent_workspace
  belongs_to :agent_client
  belongs_to :agent_trip, optional: true
  validates :body, presence: true, length: { maximum: 5000 }
  validate do
    errors.add(:agent_client, "pertenece a otro espacio") unless agent_client&.agent_workspace_id == agent_workspace_id
    errors.add(:agent_trip, "pertenece a otro espacio") if agent_trip && agent_trip.agent_workspace_id != agent_workspace_id
  end
end
