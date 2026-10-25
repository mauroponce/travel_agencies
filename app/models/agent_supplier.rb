class AgentSupplier < ApplicationRecord
  belongs_to :agent_workspace
  has_many :agent_trip_revisions, dependent: :restrict_with_error
  normalizes :name, with: ->(value) { value.to_s.strip.gsub(/\s+/, " ") }
  validates :name, uniqueness: { scope: :agent_workspace_id, case_sensitive: false }, presence: true, length: { maximum: 200 }
  validates :status, inclusion: { in: %w[active paused] }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :website, format: { with: %r{\Ahttps?://[^\s]+\z}, message: "debe comenzar con https:// o http://" }, allow_blank: true
  scope :active, -> { where(status: "active") }
  def active? = status == "active"
end
