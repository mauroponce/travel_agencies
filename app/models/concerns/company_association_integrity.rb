module CompanyAssociationIntegrity
  extend ActiveSupport::Concern

  class_methods do
    def validates_same_company(*association_names)
      validate do
        association_names.each do |association_name|
          record = public_send(association_name)
          next unless record

          associated_company_id = if record.respond_to?(:company_id)
            record.company_id
          elsif record.respond_to?(:company)
            record.company&.id
          end
          errors.add(association_name, "debe pertenecer a la empresa") if associated_company_id != company_id
        end
      end
    end
  end
end
