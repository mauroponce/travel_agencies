abort "not disposable staging" unless Rails.env.staging? && PlatformHosts.base_domain == "smoke.example.test"
trip = AgentTrip.find_by!(slug: "smoke-public")
abort "publication not restored" unless trip.status == "published"
revision = trip.published_revision
abort "PDF lost" unless revision.flyer_source.download == File.binread(Rails.root.join("test/fixtures/files/agent.pdf"))
abort "JPEG lost" unless revision.cover.download.start_with?("\xFF\xD8\xFF".b)
abort "agency data lost" unless Company.find_by!(slug: "agency").destinations.find_by(name: "Mendoza")
abort "source import lost" unless AgentImport.find_by!(idempotency_key: "smoke-import").source.download == revision.flyer_source.download
legacy = AgentWorkspace.find_by!(slug: "legacy-private")
client = legacy.agent_clients.sole
abort "private data lost" unless client.name == "PRIVATE-SMOKE-CLIENT" && client.notes.sole.body == "PRIVATE-SMOKE-NOTE"
abort "historical plan altered" unless legacy.agent_subscription.price_cents == 1700 && !legacy.agent_subscription.entitled?
active_client = trip.agent_workspace.agent_clients.sole
abort "active note reference lost" unless active_client.notes.sole.agent_trip_id == trip.id
[ [ client, %w[name phone email] ], [ client.notes.sole, %w[body] ], [ active_client, %w[name phone email] ], [ active_client.notes.sole, %w[body] ] ].each do |record, fields|
  fields.each { |field| abort "plaintext contact survived" unless record.encrypted_attribute?(field) }
end
puts "Original PDF, JPEG, agency data and published revision: OK"
