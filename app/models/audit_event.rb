class AuditEvent < ApplicationRecord
  belongs_to :company, optional: true
  belongs_to :actor, class_name: "User", optional: true
  validates :action, :auditable_type, :auditable_id, :occurred_at, presence: true

  def readonly?
    persisted?
  end
end
