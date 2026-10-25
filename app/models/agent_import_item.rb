class AgentImportItem < ApplicationRecord
  belongs_to :agent_workspace
  belongs_to :agent_import
  belongs_to :agent_trip, optional: true
  belongs_to :agent_trip_revision, optional: true
  validates :position, uniqueness: { scope: :agent_import_id }
end
