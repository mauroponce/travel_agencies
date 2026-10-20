module Memberships
  class UpdateAccess
    class LastAdministrator < StandardError; end

    def self.call(membership:, attributes:)
      new(membership:, attributes:).call
    end

    def initialize(membership:, attributes:)
      @membership = membership
      @attributes = attributes
    end

    def call
      ApplicationRecord.transaction do
        @membership.company.lock!
        @membership.lock!
        protect_last_administrator!
        update_membership!
        update_reseller_authorization!
      end
      @membership
    end

    private

    def protect_last_administrator!
      requested_status = @attributes[:status].presence
      return unless requested_status && requested_status != "active"
      return unless @membership.active? && @membership.role?("admin")

      another_admin = Membership.active.joins(:membership_roles)
        .where(company: @membership.company, membership_roles: { role: "admin" })
        .where.not(id: @membership.id).exists?
      raise LastAdministrator, "No podés suspender o revocar al último administrador activo de la agencia." unless another_admin
    end

    def update_membership!
      @membership.update!(status: @attributes[:status]) if @attributes[:status].present?
      @membership.update!(commercial_phone: @attributes[:commercial_phone]) if @attributes.key?(:commercial_phone)
    end

    def update_reseller_authorization!
      return unless @membership.reseller_authorization && @attributes.key?(:auto_confirm_enabled)

      @membership.reseller_authorization.update!(auto_confirm_enabled: @attributes[:auto_confirm_enabled] == "1")
    end
  end
end
