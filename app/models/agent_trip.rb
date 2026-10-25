class AgentTrip < ApplicationRecord
  belongs_to :agent_workspace
  belongs_to :current_revision, class_name: "AgentTripRevision", optional: true
  belongs_to :published_revision, class_name: "AgentTripRevision", optional: true
  has_many :revisions, class_name: "AgentTripRevision", dependent: :restrict_with_error
  has_many :agent_import_items, dependent: :restrict_with_error
  before_validation(on: :create) { self.slug ||= SecureRandom.hex(10) }
  validates :slug, format: { with: /\A[a-z0-9][a-z0-9_-]*\z/ }, presence: true, uniqueness: { scope: :agent_workspace_id }
  validates :status, inclusion: { in: %w[draft published unpublished archived] }
  validate do
    errors.add(:slug, "es permanente") if persisted? && will_save_change_to_slug?
    [ current_revision, published_revision ].compact.each do |revision|
      errors.add(:base, "La revisión pertenece a otro viaje") unless revision.agent_trip_id == id && revision.agent_workspace_id == agent_workspace_id
    end
  end

  scope :publicly_visible, -> {
    joins(published_revision: :agent_supplier).where(status: "published", agent_suppliers: { status: "active" })
      .where("agent_trip_revisions.departs_on >= ?", Date.current)
  }

  def publish!
    agent_workspace.with_lock do
      unless agent_workspace.active?
        errors.add(:agent_workspace, "está suspendido")
        raise ActiveRecord::RecordInvalid, self
      end
      with_lock do
        revision = current_revision
        raise ActiveRecord::RecordInvalid, self unless revision
        revision.validate_for_publication!
        update!(status: "published", published_revision: revision)
      end
    end
  end

  def expired? = current_revision&.departs_on.present? && current_revision.departs_on < Date.current
end
