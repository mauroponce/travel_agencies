class PushSubscription < ApplicationRecord
  belongs_to :user
  encrypts :endpoint, deterministic: true
  encrypts :p256dh
  encrypts :auth
  validates :endpoint, :p256dh, :auth, presence: true
end
