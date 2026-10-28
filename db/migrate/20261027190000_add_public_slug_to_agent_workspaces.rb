class AddPublicSlugToAgentWorkspaces < ActiveRecord::Migration[8.1]
  def up
    add_column :agent_workspaces, :slug, :string
    execute "UPDATE agent_workspaces SET slug = subdomain"
    # Preserve existing public addresses while avoiding collisions with app routes.
    reserved = %w[www admin auth api platform app mail smtp static assets cdn status support
      agente up manifest service-worker session test onboarding context dashboard
      paquetes salidas ofertas reservas solicitudes pagos rendiciones notificaciones
      push_subscriptions catalogos equipo comisiones viajes formularios internal rails cable brand icon favicon robots]
    rows = select_all("SELECT id, slug FROM agent_workspaces")
    occupied = rows.map { |row| row["slug"] }.to_set
    rows.each do |row|
      next unless reserved.include?(row["slug"])
      suffix = 2
      suffix += 1 while occupied.include?("#{row['slug']}-#{suffix}")
      candidate = "#{row['slug']}-#{suffix}"
      execute "UPDATE agent_workspaces SET slug = #{quote(candidate)} WHERE id = #{quote(row['id'])}"
      occupied << candidate
    end
    change_column_null :agent_workspaces, :slug, false
    add_index :agent_workspaces, :slug, unique: true
    change_column_null :agent_workspaces, :subdomain, true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Los agentes con slug no tienen subdominio."
  end
end
