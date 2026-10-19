class MembershipRole < ApplicationRecord
  ROLES = %w[admin reseller coordinator].freeze

  belongs_to :membership
  validates :role, inclusion: { in: ROLES }, uniqueness: { scope: :membership_id }
end
