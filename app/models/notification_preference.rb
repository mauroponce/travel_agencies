class NotificationPreference < ApplicationRecord
  belongs_to :membership
  validates :event_type, presence: true, uniqueness: { scope: :membership_id }
end
