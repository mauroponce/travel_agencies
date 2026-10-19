class RemittancesController < ApplicationController
  before_action -> { require_role!("admin", "reseller") }
  before_action :set_remittance, only: %i[show verify]

  def index
    scope = Remittance.where(company: current_company).includes(:reseller_membership, :remittance_allocations)
    scope = scope.where(reseller_membership: current_membership) if current_role == "reseller"
    @remittances = scope.order(created_at: :desc)
    @available_payments = CustomerPayment.where(company: current_company, status: %w[declared partially_remitted])
    @available_payments = @available_payments.where(received_by_membership: current_membership) if current_role == "reseller"
    @available_payments = @available_payments.select { |payment| payment.pending_remittance_cents.positive? }
  end

  def show; end

  def create
    require_role!("reseller")
    allocations = params.fetch(:allocations, {}).to_unsafe_h
    requested = allocations.to_h.transform_values { |amount| MoneyParser.call(amount) }.select { |_id, amount| amount.positive? }
    return redirect_to(remittances_path, alert: "Seleccioná al menos un cobro con un importe válido.") if requested.empty?
    remittance = Remittances::Create.call(company: current_company, membership: current_membership, actor: current_user,
      allocations: requested, method: params[:method], declared_on: params[:declared_on] || Date.current,
      notes: params[:notes], proof: params[:proof])
    redirect_to remittance, notice: "Rendición declarada; queda pendiente de verificación."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to remittances_path, alert: error.record.errors.full_messages.to_sentence.presence || "La rendición no es válida."
  rescue MoneyParser::InvalidAmount => error
    redirect_to remittances_path, alert: error.message
  end

  def verify
    require_role!("admin")
    @remittance.verify!(current_user)
    AuditRecorder.call(action: "remittance.verified", auditable: @remittance, changeset: { amount_cents: @remittance.amount_cents })
    NotificationDispatcher.dispatch([ @remittance.reseller_membership.user ], company: current_company,
      event_type: "remittance_verified", title: "Rendición verificada", body: "#{@remittance.code} fue recibida por la empresa.",
      action_url: remittance_path(@remittance))
    redirect_to @remittance, notice: "Recepción verificada."
  end

  private

  def set_remittance
    scope = Remittance.where(company: current_company)
    scope = scope.where(reseller_membership: current_membership) if current_role == "reseller"
    @remittance = scope.find(params[:id])
  end
end
