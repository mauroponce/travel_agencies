key_seed = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY", Rails.application.secret_key_base)

Rails.application.config.active_record.encryption.primary_key = Digest::SHA256.hexdigest("primary:#{key_seed}")
Rails.application.config.active_record.encryption.deterministic_key = Digest::SHA256.hexdigest("deterministic:#{key_seed}")
Rails.application.config.active_record.encryption.key_derivation_salt = Digest::SHA256.hexdigest("salt:#{key_seed}")
