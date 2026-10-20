class EnforceAuthenticationTenantScope < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :company_domains, %i[id company_id], unique: true, algorithm: :concurrently,
      name: "uidx_company_domains_id_company", if_not_exists: true
    add_index :authentication_requests, %i[id company_id], unique: true, algorithm: :concurrently,
      name: "uidx_authentication_requests_id_company", if_not_exists: true

    add_foreign_key :authentication_requests, :company_domains,
      column: %i[company_domain_id company_id], primary_key: %i[id company_id],
      name: "fk_auth_requests_domain_company", validate: false
    add_foreign_key :authentication_codes, :authentication_requests,
      column: %i[authentication_request_id company_id], primary_key: %i[id company_id],
      name: "fk_auth_codes_request_company", validate: false
    add_foreign_key :authentication_codes, :memberships,
      column: %i[membership_id company_id], primary_key: %i[id company_id],
      name: "fk_auth_codes_membership_company", validate: false

    validate_foreign_key :authentication_requests, name: "fk_auth_requests_domain_company"
    validate_foreign_key :authentication_codes, name: "fk_auth_codes_request_company"
    validate_foreign_key :authentication_codes, name: "fk_auth_codes_membership_company"
  end

  def down
    remove_foreign_key :authentication_codes, name: "fk_auth_codes_membership_company"
    remove_foreign_key :authentication_codes, name: "fk_auth_codes_request_company"
    remove_foreign_key :authentication_requests, name: "fk_auth_requests_domain_company"
    remove_index :authentication_requests, name: "uidx_authentication_requests_id_company"
    remove_index :company_domains, name: "uidx_company_domains_id_company"
  end
end
