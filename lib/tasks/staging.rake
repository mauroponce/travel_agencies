namespace :staging do
  desc "Provision two isolated fictitious agencies and administrator invitations"
  task provision: :environment do
    companies = StagingProvisioner.call
    companies.each { |company| puts "#{company.name}: #{company.platform_domain.hostname}" }
    puts "Staging provisioned. OAuth users accept matching invitations on first sign-in."
  end
end
