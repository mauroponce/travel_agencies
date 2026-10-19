class User < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :companies, through: :memberships
  has_many :notifications, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
  has_many :platform_roles, dependent: :destroy

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }
  validates :google_sub, :email, :name, presence: true
  validates :google_sub, :email, uniqueness: true
  validates :phone, format: { with: /\A\d{8,15}\z/, allow_blank: true }

  def platform_operator?
    platform_roles.exists?(role: "operator")
  end
end
