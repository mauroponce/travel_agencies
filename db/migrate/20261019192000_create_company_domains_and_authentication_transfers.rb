class CreateCompanyDomainsAndAuthenticationTransfers < ActiveRecord::Migration[8.1]
  def up
    create_table :company_domains, id: :uuid do |t|
      t.references :company, type: :uuid, null: false, foreign_key: true
      t.string :hostname, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.boolean :primary, null: false, default: false
      t.string :verification_token_digest
      t.string :cname_target
      t.string :tls_status, null: false, default: "pending"
      t.datetime :verified_at
      t.datetime :activated_at
      t.datetime :disabled_at
      t.timestamps
    end
    add_index :company_domains, "lower(hostname)", unique: true, name: "uidx_company_domains_lower_hostname"
    add_index :company_domains, :company_id, unique: true, where: "kind = 'platform_subdomain'",
      name: "uidx_company_domains_platform_per_company"
    add_index :company_domains, :company_id, unique: true, where: "\"primary\" = true",
      name: "uidx_company_domains_primary_per_company"
    add_check_constraint :company_domains, "kind IN ('platform_subdomain', 'custom')", name: "company_domains_kind_valid"
    add_check_constraint :company_domains, "status IN ('pending', 'verified', 'active', 'disabled')", name: "company_domains_status_valid"
    add_check_constraint :company_domains, "tls_status IN ('pending', 'ready', 'failed')", name: "company_domains_tls_status_valid"
    add_check_constraint :company_domains, "hostname = lower(hostname) AND hostname !~ '\\.$'", name: "company_domains_hostname_normalized"
    add_check_constraint :company_domains, "NOT \"primary\" OR status = 'active'", name: "company_domains_primary_active"

    create_table :authentication_requests, id: :uuid do |t|
      t.references :company, type: :uuid, foreign_key: true
      t.references :company_domain, type: :uuid, foreign_key: true
      t.string :return_hostname, null: false
      t.string :token_digest, null: false
      t.string :browser_nonce_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.timestamps
    end
    add_index :authentication_requests, :token_digest, unique: true
    add_check_constraint :authentication_requests,
      "(company_id IS NULL AND company_domain_id IS NULL) OR (company_id IS NOT NULL AND company_domain_id IS NOT NULL)",
      name: "authentication_requests_scope_consistent"

    create_table :authentication_codes, id: :uuid do |t|
      t.references :authentication_request, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :company, type: :uuid, foreign_key: true
      t.references :membership, type: :uuid, foreign_key: true
      t.string :target_hostname, null: false
      t.string :token_digest, null: false
      t.string :browser_nonce_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :authentication_codes, :token_digest, unique: true
    add_check_constraint :authentication_codes,
      "(company_id IS NULL AND membership_id IS NULL) OR (company_id IS NOT NULL AND membership_id IS NOT NULL)",
      name: "authentication_codes_scope_consistent"

    add_reference :push_subscriptions, :company, type: :uuid, foreign_key: true
    add_column :push_subscriptions, :origin_hostname, :string

    base_domain = ENV.fetch("PLATFORM_BASE_DOMAIN", Rails.env.test? ? "example.test" : "lvh.me").downcase.delete_suffix(".")
    reserved = %w[www admin auth api platform app mail smtp static assets cdn status support]
    select_all("SELECT id, slug FROM companies ORDER BY created_at, id").each do |company|
      subdomain = company.fetch("slug").to_s.downcase.gsub(/[^a-z0-9-]/, "-").gsub(/\A-+|-+\z/, "")
      raise "Company #{company.fetch('id')} has a reserved or invalid slug for tenant hostname" if
        subdomain.blank? || reserved.include?(subdomain)

      hostname = "#{subdomain}.#{base_domain}"
      execute <<~SQL.squish
        INSERT INTO company_domains
          (id, company_id, hostname, kind, status, "primary", tls_status, verified_at, activated_at, created_at, updated_at)
        VALUES
          (gen_random_uuid(), #{quote(company.fetch('id'))}, #{quote(hostname)}, 'platform_subdomain', 'active', true,
           'ready', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
  end

  def down
    remove_column :push_subscriptions, :origin_hostname
    remove_reference :push_subscriptions, :company
    drop_table :authentication_codes
    drop_table :authentication_requests
    drop_table :company_domains
  end
end
