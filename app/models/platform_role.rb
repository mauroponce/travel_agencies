class PlatformRole < ApplicationRecord
  belongs_to :user
  validates :role, inclusion: { in: %w[operator] }
end
