class Notification < ApplicationRecord
  belongs_to :company, optional: true
  belongs_to :user
  validates :event_type, :title, :body, :deduplication_key, presence: true

  scope :unread, -> { where(read_at: nil) }
end
