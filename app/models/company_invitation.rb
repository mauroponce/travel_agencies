class CompanyInvitation < ApplicationRecord
  belongs_to :company
  belongs_to :invited_by, class_name: "User", optional: true

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }
  validates :email, presence: true
  validate :roles_are_valid

  scope :available, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.issue!(company:, email:, roles:, invited_by: nil, expires_in: 7.days)
    token = SecureRandom.urlsafe_base64(32)
    invitation = create!(company:, email:, roles:, invited_by:, expires_at: expires_in.from_now,
      token_digest: Digest::SHA256.hexdigest(token))
    [ invitation, token ]
  end

  def accept!(user)
    with_lock do
      if accepted_at.present?
        membership = company.memberships.find_by(user:)
        return membership if membership && email.casecmp?(user.email)
      end
      raise ActiveRecord::RecordInvalid, self unless email.casecmp?(user.email) && expires_at.future? && revoked_at.nil?

      membership = company.memberships.find_or_create_by!(user:) { |record| record.status = "active" }
      membership.update!(status: "active")
      roles.each { |role| membership.membership_roles.find_or_create_by!(role:) }
      membership.create_reseller_authorization! if roles.include?("reseller") && membership.reseller_authorization.nil?
      update!(accepted_at: Time.current)
      membership
    end
  end

  private

  def roles_are_valid
    errors.add(:roles, "contiene perfiles inválidos") unless roles.present? && (roles - MembershipRole::ROLES).empty?
  end
end
