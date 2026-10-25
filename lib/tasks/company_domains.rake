namespace :company_domains do
  desc "Audit persisted tenant domains against model and infrastructure configuration"
  task audit: :environment do
    result = CompanyDomains::Audit.call
    result.findings.each { |finding| puts "#{finding.severity.to_s.upcase} #{finding.code}: #{finding.message}" }
    puts "Company domain audit: OK" if result.findings.empty?
    failures = result.errors
    failures += result.warnings if ENV["STRICT_INFRASTRUCTURE"] == "true"
    abort "Found #{failures.size} company domain violation(s)" if failures.any?
  end

  namespace :base_migration do
    desc "Plan a base-domain migration without changing data: rake company_domains:base_migration:plan[old,new]"
    task :plan, %i[from to] => :environment do |_task, args|
      plan = CompanyDomains::BaseDomainMigration.plan(from: args.fetch(:from), to: args.fetch(:to))
      plan.mappings.each { |mapping| puts "#{mapping.from} -> #{mapping.to}" }
      plan.errors.each { |error| warn "ERROR: #{error}" }
      abort "Base-domain migration is not safe" unless plan.safe?
    end

    desc "Apply a planned migration transactionally; requires CONFIRM=old->new and PLATFORM_BASE_DOMAIN=new"
    task :apply, %i[from to] => :environment do |_task, args|
      expected = "#{args.fetch(:from)}->#{args.fetch(:to)}"
      abort "Set CONFIRM=#{expected}" unless ENV["CONFIRM"] == expected
      plan = CompanyDomains::BaseDomainMigration.apply!(from: args[:from], to: args[:to])
      puts "Updated #{plan.mappings.size} permanent subdomain(s)"
    end

    desc "Rollback uses the same safe operation in reverse: rake company_domains:base_migration:rollback[new,old]"
    task :rollback, %i[from to] => :environment do |_task, args|
      expected = "#{args.fetch(:from)}->#{args.fetch(:to)}"
      abort "Set CONFIRM=#{expected}" unless ENV["CONFIRM"] == expected
      plan = CompanyDomains::BaseDomainMigration.apply!(from: args[:from], to: args[:to])
      puts "Restored #{plan.mappings.size} permanent subdomain(s)"
    end
  end
end
