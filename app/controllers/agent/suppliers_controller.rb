module Agent
  class SuppliersController < BaseController
    before_action :set_supplier, only: %i[show edit update destroy]
    def index
      scope = current_agent_workspace.agent_suppliers
      if params[:q].present?
        term = "%#{AgentSupplier.sanitize_sql_like(params[:q].to_s.first(200))}%"
        scope = scope.where("name ILIKE :q OR contact_name ILIKE :q OR email ILIKE :q OR phone ILIKE :q", q: term)
      end
      @suppliers, @pagination = paginate(scope.order(:name, :id))
      @counts = current_agent_workspace.agent_trips.joins(:current_revision).group("agent_trip_revisions.agent_supplier_id").count
    end
    def new = @supplier = current_agent_workspace.agent_suppliers.new
    def show; end
    def edit; end
    def create
      @supplier = current_agent_workspace.agent_suppliers.new(supplier_params)
      if @supplier.save
        audit("agent_supplier.created", @supplier)
        redirect_to agent_supplier_path(@supplier), notice: "Empresa registrada."
      else
        render :new, status: :unprocessable_entity
      end
    end
    def update
      if @supplier.update(supplier_params)
        audit("agent_supplier.updated", @supplier)
        redirect_to agent_supplier_path(@supplier), notice: "Empresa actualizada."
      else
        render :edit, status: :unprocessable_entity
      end
    end
    def destroy
      if @supplier.destroy
        audit("agent_supplier.deleted", @supplier)
        redirect_to agent_suppliers_path, notice: "Empresa eliminada."
      else
        redirect_to agent_supplier_path(@supplier), alert: "La empresa tiene viajes asociados. Podés pausarla para ocultarlos del catálogo."
      end
    end
    private
    def set_supplier = @supplier = current_agent_workspace.agent_suppliers.find(params[:id])
    def supplier_params = params.expect(agent_supplier: [ :name, :contact_name, :phone, :email, :commercial_terms, :commission_terms, :website, :notes, :status ])
  end
end
