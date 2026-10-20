class AuditRecorder
  SENSITIVE_KEYS = %w[document_number full_name notes phone commercial_phone google_sub token token_digest auth p256dh endpoint].freeze

  def self.call(action:, auditable:, actor: Current.user, company: Current.company, changeset: {})
    AuditEvent.create!(company:, actor:, action:, auditable_type: auditable.class.name,
      auditable_id: auditable.id, changeset: filter_sensitive(changeset),
      request_id: Current.request_id, ip_address: Current.ip_address, occurred_at: Time.current)
  end

  def self.filter_sensitive(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, nested), filtered|
        filtered[key.to_s] = filter_sensitive(nested) unless SENSITIVE_KEYS.include?(key.to_s)
      end
    when Array
      value.map { |nested| filter_sensitive(nested) }
    else
      value
    end
  end
  private_class_method :filter_sensitive
end
