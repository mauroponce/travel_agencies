class PushSubscription < ApplicationRecord
  belongs_to :user
  belongs_to :company, optional: true
  encrypts :endpoint, deterministic: true
  encrypts :p256dh
  encrypts :auth
  validates :endpoint, :p256dh, :auth, presence: true
  validates :origin_hostname, presence: true
end
