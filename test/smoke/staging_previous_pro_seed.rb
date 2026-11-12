# Simulate the previous deployed schema and its plaintext contacts, including an expired plan.
abort "not disposable staging" unless Rails.env.staging? && PlatformHosts.base_domain == "smoke.example.test"
workspace = AgentWorkspace.create!(business_name: "Legacy private", public_name: "Legacy", whatsapp: "5491155550102", invited_email: "legacy@example.invalid", slug: "legacy-private")
workspace.agent_subscription.update!(price_cents: 1700, trial_starts_at: 30.days.ago, trial_ends_at: 16.days.ago)
class LegacySmokeClient < ApplicationRecord
  self.table_name = "agent_clients"
end
class LegacySmokeNote < ApplicationRecord
  self.table_name = "agent_client_notes"
end
client = LegacySmokeClient.create!(agent_workspace_id: workspace.id, name: "PRIVATE-SMOKE-CLIENT", phone: "5491155550102", email: "PRIVATE-SMOKE-EMAIL@example.invalid")
LegacySmokeNote.create!(agent_workspace_id: workspace.id, agent_client_id: client.id, body: "PRIVATE-SMOKE-NOTE")
puts "Previous Pro plaintext contacts and historical expired subscription seeded"
