class ResellerAuthorization < ApplicationRecord
  belongs_to :membership
  has_many :commission_rules, foreign_key: :reseller_membership_id, dependent: :destroy

  before_validation :set_public_code, on: :create
  validates :public_code, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[active paused revoked] }

  def active?
    status == "active" && membership.role?("reseller")
  end

  private

  def set_public_code
    self.public_code ||= SecureRandom.urlsafe_base64(9)
  end
end
