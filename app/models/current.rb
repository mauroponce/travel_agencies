class Current < ActiveSupport::CurrentAttributes
  attribute :user, :company, :membership, :role, :request_id, :ip_address

  resets { Time.zone = "America/Argentina/Buenos_Aires" }
end
