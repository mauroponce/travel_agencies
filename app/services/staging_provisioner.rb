class StagingProvisioner
  class UnsafeEnvironment < StandardError; end

  def self.call
    raise UnsafeEnvironment, "StagingProvisioner solo puede ejecutarse con RAILS_ENV=staging" unless Rails.env.staging?
    raise UnsafeEnvironment, "Definí ENABLE_STAGING_DATA=true" unless ENV["ENABLE_STAGING_DATA"] == "true"

    new.call
  end

  def call
    ApplicationRecord.transaction do
      agency_one = DemoProvisioner.call
      agency_one.update!(name: "Agencia Uno Staging")
      agency_two = Company.find_or_create_by!(slug: "agencia-dos") do |company|
        company.name = "Agencia Dos Staging"
        company.email = "agencia-dos@staging.invalid"
      end
      invite(agency_one, ENV.fetch("STAGING_AGENCY_ONE_ADMIN_EMAIL"))
      invite(agency_two, ENV.fetch("STAGING_AGENCY_TWO_ADMIN_EMAIL"))
      [ agency_one, agency_two ]
    end
  end

  private

  def invite(company, email)
    normalized = email.to_s.strip.downcase
    return if CompanyInvitation.available.where(company:).where("lower(email) = ?", normalized).exists?

    CompanyInvitation.issue!(company:, email: normalized, roles: %w[admin])
  end
end
