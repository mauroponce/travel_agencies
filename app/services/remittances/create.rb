module Remittances
  class Create
    def self.call(**arguments) = new(**arguments).call

    def initialize(company:, membership:, actor:, allocations:, method:, declared_on:, notes: nil, proof: nil)
      @company = company
      @membership = membership
      @actor = actor
      @allocations = allocations
      @method = method
      @declared_on = declared_on
      @notes = notes
      @proof = proof
    end

    def call
      ApplicationRecord.transaction do
        payments = CustomerPayment.where(company: @company, received_by_membership: @membership)
          .where(id: @allocations.keys).order(:id).lock.to_a
        raise Pundit::NotAuthorizedError unless payments.size == @allocations.size

        remittance = Remittance.create!(company: @company, reseller_membership: @membership,
          declared_by: @actor, code: "RE-#{SecureRandom.hex(3).upcase}", amount_cents: @allocations.values.sum,
          method: @method, declared_on: @declared_on, notes: @notes)
        payments.each do |payment|
          amount = @allocations.fetch(payment.id)
          raise ActiveRecord::RecordInvalid, payment if amount <= 0 || amount > payment.pending_remittance_cents

          remittance.remittance_allocations.create!(customer_payment: payment, amount_cents: amount)
          payment.update!(status: "partially_remitted") unless payment.status == "verified"
        end
        remittance.proof.attach(@proof) if @proof.present?
        remittance
      end
    end
  end
end
