class Current < ActiveSupport::CurrentAttributes
  attribute :user, :company, :company_domain, :membership, :role, :host_scope, :request_id, :ip_address

  resets { Time.zone = "America/Argentina/Buenos_Aires" }
end
