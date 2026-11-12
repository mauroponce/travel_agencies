class AgentSubscription < ApplicationRecord
  belongs_to :agent_workspace
  validates :agent_workspace_id, uniqueness: true
  validates :status, inclusion: { in: %w[trialing active inactive] }
  validates :origin, inclusion: { in: %w[signup pilot_transition] }
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: %w[USD] }
  validates :trial_starts_at, :trial_ends_at, presence: true
  validate do
    errors.add(:trial_ends_at, "debe ser posterior al inicio") if trial_starts_at && trial_ends_at && trial_ends_at <= trial_starts_at
    if current_period_starts_at.present? != current_period_ends_at.present? ||
        (current_period_ends_at && current_period_starts_at && current_period_ends_at <= current_period_starts_at)
      errors.add(:current_period_ends_at, "no es válido")
    end
  end

  def self.price_cents = Integer(ENV.fetch("AGENT_PRO_PRICE_CENTS", "1900")).clamp(0, 1_000_000)
  def self.trial_days = Integer(ENV.fetch("AGENT_PRO_TRIAL_DAYS", "14")).clamp(1, 90)
  def self.grace_days = Integer(ENV.fetch("AGENT_PRO_GRACE_DAYS", "0")).clamp(0, 30)
  def self.monthly_units = Integer(ENV.fetch("AGENT_PRO_MONTHLY_AI_UNITS", "200")).clamp(0, 100_000)

  def ends_at = status == "trialing" ? trial_ends_at : current_period_ends_at

  def entitled?(at: Time.current)
    case status
    when "trialing" then trial_starts_at <= at && at < trial_ends_at
    when "active"
      current_period_starts_at && current_period_starts_at <= at && at < current_period_ends_at + (cancel_at_period_end ? 0 : self.class.grace_days).days
    else false
    end
  end

  def label
    return "Vencido · solo lectura" unless entitled?
    return "Transición del piloto" if status == "trialing" && origin == "pilot_transition"
    return "Prueba gratuita" if status == "trialing"
    cancel_at_period_end ? "Pro · cancelación al vencimiento" : "Pro vigente"
  end
end
