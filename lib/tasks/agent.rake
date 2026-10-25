namespace :agent do
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
