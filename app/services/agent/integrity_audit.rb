module Agent
  class IntegrityAudit
    def self.call
      findings = []
      CompanyDomain.find_each do |domain|
        findings << "Unregistered company domain #{domain.id}" unless HostnameRegistration.exists?(hostname: domain.hostname, company_id: domain.company_id)
      end
      AgentWorkspace.includes(:hostname_registration).find_each do |workspace|
        findings << "Invalid agent hostname #{workspace.id}" if workspace.subdomain.present? && workspace.hostname_registration&.hostname != workspace.hostname
      end
      relations = { AgentTripRevision => [ :agent_trip, :agent_supplier ], AgentImportItem => [ :agent_import, :agent_trip, :agent_trip_revision ], AgentAiExecution => [ :agent_import, :agent_search ] }
      relations.each do |model, associations|
        model.includes(*associations).find_each do |record|
          associations.each do |association|
            target = record.public_send(association)
            findings << "Cross-workspace #{model.name} #{record.id}: #{association}" if target && target.agent_workspace_id != record.agent_workspace_id
          end
        end
      end
      AgentTrip.includes(:current_revision, :published_revision).find_each do |trip|
        [ trip.current_revision, trip.published_revision ].compact.each do |revision|
          findings << "Invalid revision pointer #{trip.id}" unless revision.agent_trip_id == trip.id && revision.agent_workspace_id == trip.agent_workspace_id
        end
      end
      findings
    end
  end
end
