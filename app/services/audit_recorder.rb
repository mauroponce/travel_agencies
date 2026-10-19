class AuditRecorder
  SENSITIVE_KEYS = %w[document_number google_sub token token_digest auth p256dh endpoint].freeze

  def self.call(action:, auditable:, actor: Current.user, company: Current.company, changeset: {})
    AuditEvent.create!(company:, actor:, action:, auditable_type: auditable.class.name,
      auditable_id: auditable.id, changeset: changeset.stringify_keys.except(*SENSITIVE_KEYS),
      request_id: Current.request_id, ip_address: Current.ip_address, occurred_at: Time.current)
  end
end
