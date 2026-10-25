class AgentSearch < ApplicationRecord
  include AgentAiTask
  validates :query, presence: true, length: { maximum: 3000 }
end
