class HostnameRegistration < ApplicationRecord
  belongs_to :company, optional: true
  belongs_to :agent_workspace, optional: true
  normalizes :hostname, with: ->(value) { PlatformHosts.normalize(value) }
  validates :hostname, presence: true, uniqueness: { case_sensitive: false }, format: { with: CompanyDomain::HOSTNAME_PATTERN }
  validate { errors.add(:base, "El hostname requiere un único propietario") unless company_id.present? ^ agent_workspace_id.present? }
  validate do
    errors.add(:hostname, "no coincide con el subdominio del agente") if agent_workspace && hostname != agent_workspace.hostname
  end

  def self.reserve_company!(hostname, company_id)
    registration = find_or_initialize_by(hostname: PlatformHosts.normalize(hostname))
    unless registration.new_record? || registration.company_id == company_id
      raise ActiveRecord::RecordNotUnique, "Hostname ocupado"
    end
    registration.update!(company_id:)
  end
end
