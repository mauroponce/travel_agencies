class AddWebsiteSectionsToAgentWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_workspaces, :show_presentation, :boolean, default: true, null: false
    add_column :agent_workspaces, :show_catalog, :boolean, default: true, null: false
    add_column :agent_workspaces, :show_about, :boolean, default: false, null: false
    add_column :agent_workspaces, :about_text, :text
  end
end
