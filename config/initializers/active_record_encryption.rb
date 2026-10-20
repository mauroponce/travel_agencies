key_seed = ENV["ACTIVE_RECORD_ENCRYPTION_KEY"].presence
if Rails.env.production? && key_seed.blank? && ENV["SECRET_KEY_BASE_DUMMY"] != "1"
  raise "ACTIVE_RECORD_ENCRYPTION_KEY es obligatoria en producción y debe ser independiente de SECRET_KEY_BASE"
end
if Rails.env.production? && key_seed.present? && key_seed == Rails.application.secret_key_base
  raise "ACTIVE_RECORD_ENCRYPTION_KEY no puede ser igual a SECRET_KEY_BASE"
end
key_seed ||= Rails.application.secret_key_base

Rails.application.config.active_record.encryption.primary_key = Digest::SHA256.hexdigest("primary:#{key_seed}")
Rails.application.config.active_record.encryption.deterministic_key = Digest::SHA256.hexdigest("deterministic:#{key_seed}")
Rails.application.config.active_record.encryption.key_derivation_salt = Digest::SHA256.hexdigest("salt:#{key_seed}")
