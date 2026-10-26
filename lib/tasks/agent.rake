namespace :agent do
  desc "Check DB/Redis/Sidekiq and report AI failures and approximate token usage (read only)"
  task operations: :environment do
    require "sidekiq/api"
    abort "Database unavailable" unless ApplicationRecord.connection.select_value("SELECT 1") == 1
    abort "Pending migrations" if ApplicationRecord.connection_pool.migration_context.needs_migration?
    abort "Redis unavailable" unless Sidekiq.redis { |redis| redis.call("PING") } == "PONG"
    workers = Sidekiq::ProcessSet.new.select { |process| process["beat"].to_f > 30.seconds.ago.to_f }
    abort "No recent Sidekiq heartbeat" if workers.empty?
    puts "DB, migrations, Redis, Sidekiq: OK (#{workers.size} workers)"
    puts "Sidekiq queued=#{Sidekiq::Stats.new.enqueued} retries=#{Sidekiq::RetrySet.new.size} dead=#{Sidekiq::DeadSet.new.size}"
    recent = AgentAiExecution.where("created_at >= ?", 24.hours.ago)
    puts "AI last 24h: executions=#{recent.count} errors=#{recent.where(status: 'error').count} discarded=#{recent.where(status: 'discarded').count} reported_tokens=#{recent.sum(Arel.sql("COALESCE((usage->>'totalTokenCount')::bigint, 0)"))}"
    stale = [ AgentImport, AgentSearch ].sum do |model|
      model.joins(:agent_workspace).where(agent_workspaces: { status: "active" }, status: %w[pending processing]).where("#{model.table_name}.updated_at < ?", 10.minutes.ago).count
    end
    abort "AI tasks stuck for over 10 minutes: #{stale}" if stale.positive?
    abort "Sidekiq dead jobs require inspection" if Sidekiq::DeadSet.new.size.positive?
  end

  desc "Finalize shared hostname ownership after ALL web/worker processes run the registry-aware release"
  task finalize_hosts: :environment do
    connection = ApplicationRecord.connection
    ApplicationRecord.transaction do
      connection.execute("LOCK TABLE company_domains IN SHARE ROW EXCLUSIVE MODE")
      CompanyDomain.find_each { |domain| HostnameRegistration.reserve_company!(domain.hostname, domain.company_id) }
      unless connection.foreign_key_exists?(:company_domains, name: "fk_company_domain_registered_host")
        connection.add_foreign_key :company_domains, :hostname_registrations,
          column: %i[hostname company_id], primary_key: %i[hostname company_id],
          name: "fk_company_domain_registered_host", validate: false
      end
    end
    connection.validate_foreign_key :company_domains, name: "fk_company_domain_registered_host"
    %i[authentication_requests authentication_codes].each do |table|
      connection.execute("UPDATE #{table} SET purpose = CASE WHEN company_id IS NULL THEN 'operator' ELSE 'company' END WHERE purpose IS NULL")
      connection.change_column_null table, :purpose, false
    end
    puts "Hostname ownership finalized. Safe to enable AGENT_ENABLED."
  end

  desc "Audit agent relations and the shared hostname registry without changing data"
  task audit: :environment do
    findings = Agent::IntegrityAudit.call
    findings.each { |finding| puts finding }
    abort "Agent integrity audit failed" if findings.any?
    puts "Agent integrity OK"
  end
end
