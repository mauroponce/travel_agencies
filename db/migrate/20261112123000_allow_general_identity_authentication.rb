class AllowGeneralIdentityAuthentication < ActiveRecord::Migration[8.1]
  def up
    %i[authentication_requests authentication_codes].each do |table|
      remove_check_constraint table, name: "#{table}_purpose"
      add_check_constraint table, constraint(table, general: true), name: "#{table}_purpose"
    end
  end

  def down
    # Old code understands operator as the platform entry purpose.
    %i[authentication_requests authentication_codes].each do |table|
      execute "UPDATE #{table} SET purpose = 'operator' WHERE purpose = 'identity'"
      remove_check_constraint table, name: "#{table}_purpose"
      add_check_constraint table, constraint(table, general: false), name: "#{table}_purpose"
    end
  end

  private

  def constraint(table, general:)
    owner = table == :authentication_requests ? "company_domain_id" : "membership_id"
    purposes = general ? "'operator', 'agent_onboarding', 'identity'" : "'operator', 'agent_onboarding'"
    "(purpose IS NULL AND agent_workspace_id IS NULL) OR (purpose = 'company' AND company_id IS NOT NULL AND #{owner} IS NOT NULL AND agent_workspace_id IS NULL) OR (purpose = 'agent' AND company_id IS NULL AND #{owner} IS NULL AND agent_workspace_id IS NOT NULL) OR (purpose IN (#{purposes}) AND company_id IS NULL AND #{owner} IS NULL AND agent_workspace_id IS NULL)"
  end
end
