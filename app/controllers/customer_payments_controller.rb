class CustomerPaymentsController < ApplicationController
  before_action -> { require_role!("admin", "reseller") }
  def index
    scope = CustomerPayment.where(company: current_company).includes(:reservation, :received_by_membership)
    scope = scope.where(received_by_membership: current_membership) if current_role == "reseller"
    @payments = scope.order(received_on: :desc)
  end

  def create
    reservation = Reservation.where(company: current_company).find(params[:reservation_id])
    if current_role == "reseller" && reservation.seller_membership_id != current_membership.id
      raise Pundit::NotAuthorizedError
    end
    attributes = payment_params
    proof = attributes.delete(:proof)
    payment = reservation.customer_payments.create!(attributes.merge(company: current_company, recorded_by: current_user,
      received_by_membership: (current_membership if current_role == "reseller")))
    payment.proof.attach(proof) if proof.present?
    redirect_to customer_payments_path, notice: "Pago declarado. La empresa todavía debe verificar la rendición."
  end

  private

  def payment_params
    raw = params.expect(customer_payment: [ :amount_cents, :method, :received_on, :notes, :proof ]).to_h.symbolize_keys
    raw[:amount_cents] = MoneyParser.call(raw[:amount_cents])
    raw
  end
end
