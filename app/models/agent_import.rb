class AgentImport < ApplicationRecord
  include AgentAiTask
  has_one_attached :source
  has_one_attached :preview
  has_many :items, -> { order(:position) }, class_name: "AgentImportItem", dependent: :restrict_with_error
end
