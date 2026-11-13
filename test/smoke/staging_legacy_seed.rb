abort "not disposable staging" unless Rails.env.staging? && PlatformHosts.base_domain == "smoke.example.test"
connection = ApplicationRecord.connection
abort "expected pre-agent schema" if connection.table_exists?(:agent_workspaces)
# Emulate the preceding agency release without running new registry-aware callbacks.
company_id = connection.select_value(<<~SQL)
  INSERT INTO companies (name, slug, created_at, updated_at)
  VALUES ('Agencia smoke', 'agency', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id
SQL
connection.execute(<<~SQL)
  INSERT INTO company_domains (company_id, hostname, kind, status, "primary", tls_status, verified_at, activated_at, created_at, updated_at)
  VALUES (#{connection.quote(company_id)}, 'agency.smoke.example.test', 'platform_subdomain', 'active', true, 'ready', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
SQL
connection.execute(<<~SQL)
  INSERT INTO destinations (company_id, name, province, created_at, updated_at)
  VALUES (#{connection.quote(company_id)}, 'Mendoza', 'Mendoza', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
SQL
puts "Legacy agency and destination saved before Asesor migrations"
