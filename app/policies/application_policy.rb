class ApplicationPolicy
  attr_reader :user, :record, :membership, :role

  def initialize(context, record)
    @user = context.user
    @membership = context.membership
    @role = context.role
    @record = record
  end

  def index? = membership.present?
  def show? = same_company?
  def create? = admin?
  def update? = admin? && same_company?
  def destroy? = admin? && same_company?

  private

  def admin? = role == "admin"
  def same_company? = record.respond_to?(:company_id) && record.company_id == membership&.company_id
end
