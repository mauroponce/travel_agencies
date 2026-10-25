module Agent
  class SaveTrip
    def self.call(workspace:, attributes:, trip: nil, item: nil, publish: false, expected_revision_id: nil, source_import: nil)
      ApplicationRecord.transaction do
        workspace.lock!
        raise Pundit::NotAuthorizedError unless workspace.active?
        raise ActiveRecord::RecordNotFound if item && item.agent_workspace_id != workspace.id
        source_import ||= item&.agent_import
        raise ActiveRecord::RecordNotFound if source_import && source_import.agent_workspace_id != workspace.id
        item&.lock!
        return item.agent_trip if item&.agent_trip_id.present?
        trip ||= workspace.agent_trips.create!
        trip.lock!
        raise ActiveRecord::RecordNotFound unless trip.agent_workspace_id == workspace.id
        if expected_revision_id && trip.current_revision_id.to_s != expected_revision_id.to_s
          raise ActiveRecord::StaleObjectError.new(trip, "guardar")
        end
        supplier = if attributes["new_supplier_name"].present?
          workspace.agent_suppliers.create!(name: attributes["new_supplier_name"])
        elsif attributes["agent_supplier_id"].present?
          workspace.agent_suppliers.find(attributes["agent_supplier_id"])
        else
          invalid = AgentTripRevision.new(attributes.slice(*AgentTripRevision::FIELDS))
          invalid.errors.add(:agent_supplier, "seleccioná una empresa o completá el nombre de una nueva")
          raise ActiveRecord::RecordInvalid, invalid
        end
        fields = attributes.slice(*AgentTripRevision::FIELDS).except("agent_supplier_id")
        fields["title"] = fields["destination"] if fields["title"].blank? && fields["destination"].present?
        revision = trip.revisions.new(fields.merge(agent_workspace: workspace, agent_supplier: supplier))
        revision.warnings = item.extracted.fetch("warnings", []) if item
        revision.evidence = item.extracted.fetch("evidence", {}) if item
        Flyer.attach!(revision:, upload: attributes["cover"], source_import:, previous: trip.current_revision)
        revision.save!
        trip.update!(current_revision: revision)
        trip.publish! if publish
        item&.update!(agent_trip: trip, agent_trip_revision: revision)
        AuditRecorder.call(action: publish ? "agent_trip.published" : "agent_trip.saved", auditable: trip)
        trip
      end
    end
  end
end
