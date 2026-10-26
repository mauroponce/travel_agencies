# Only bin/smoke-staging sets these hosts, DB and model. No real credentials or calls.
abort "not a disposable staging stack" unless Rails.env.staging? && PlatformHosts.base_domain == "smoke.example.test" && ENV["GEMINI_MODEL"] == "local-disabled"
company = Company.find_by!(slug: "agency")
abort "legacy destination lost" unless company.destinations.find_by(name: "Mendoza")
workspace = AgentWorkspace.create!(business_name: "Revendedor smoke", public_name: "Prueba", whatsapp: "5491155550101", invited_email: "pilot@example.invalid", subdomain: "reseller")
supplier = workspace.agent_suppliers.create!(name: "Organizador smoke", notes: "PRIVATE SMOKE NOTES")
task = workspace.agent_imports.create!(idempotency_key: "smoke-import")
task.source.attach(io: File.open(Rails.root.join("test/fixtures/files/agent.pdf")), filename: "agent.pdf", content_type: "application/pdf")
trip = workspace.agent_trips.create!(slug: "smoke-public")
Agent::SaveTrip.call(workspace:, trip:, source_import: task, publish: true, attributes: {
  "agent_supplier_id" => supplier.id, "title" => "Oferta smoke", "destination" => "Salta", "departs_on" => 2.months.from_now.to_date,
  "price_cents" => 45_000_000, "currency" => "ARS", "price_unit" => "per_person"
})
AgentAiJob.perform_later("import", task.id)
# Waiting is conditional, so a healthy worker completes immediately.
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
until task.reload.status == "error"
  abort "worker did not process import" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  sleep 0.25
end
abort "unexpected AI result" unless task.error_code == "configuration" && task.attempts == 1
abort "original lost" unless task.source.download == trip.reload.current_revision.flyer_source.download
puts "Synthetic PDF processed by Sidekiq without provider call; manual publication: OK"
