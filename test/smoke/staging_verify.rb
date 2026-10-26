abort "not disposable staging" unless Rails.env.staging? && PlatformHosts.base_domain == "smoke.example.test"
trip = AgentTrip.find_by!(slug: "smoke-public")
abort "publication not restored" unless trip.status == "published"
revision = trip.published_revision
abort "PDF lost" unless revision.flyer_source.download == File.binread(Rails.root.join("test/fixtures/files/agent.pdf"))
abort "JPEG lost" unless revision.cover.download.start_with?("\xFF\xD8\xFF".b)
abort "agency data lost" unless Company.find_by!(slug: "agency").destinations.find_by(name: "Mendoza")
abort "source import lost" unless AgentImport.find_by!(idempotency_key: "smoke-import").source.download == revision.flyer_source.download
puts "Original PDF, JPEG, agency data and published revision: OK"
