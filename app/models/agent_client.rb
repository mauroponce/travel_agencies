class AgentClient < ApplicationRecord
  include AgentCommercialRecord
  belongs_to :agent_workspace
  has_many :notes, class_name: "AgentClientNote", dependent: :restrict_with_error
  normalizes :name, with: ->(value) { value.to_s.strip }
  normalizes :phone, with: ->(value) { value.to_s.gsub(/[^0-9]/, "").presence }
  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }
  validates :name, presence: true, length: { maximum: 200 }
  validates :phone, presence: true
  validates :phone, format: { with: /\A[1-9]\d{7,14}\z/ }, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true, length: { maximum: 254 }
  scope :active, -> { where(archived_at: nil) }
end
