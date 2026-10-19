class Membership < ApplicationRecord
  belongs_to :company
  belongs_to :user
  has_many :membership_roles, dependent: :destroy
  has_one :reseller_authorization, dependent: :destroy
  has_many :departure_assignments, dependent: :destroy
  has_many :notification_preferences, dependent: :destroy

  validates :status, inclusion: { in: %w[active suspended revoked] }
  validates :user_id, uniqueness: { scope: :company_id }

  scope :active, -> { where(status: "active") }

  def roles
    membership_roles.pluck(:role)
  end

  def role?(role)
    status == "active" && membership_roles.exists?(role: role.to_s)
  end
end
