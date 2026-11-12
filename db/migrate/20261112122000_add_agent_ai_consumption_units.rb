class AddAgentAiConsumptionUnits < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_ai_executions, :consumption_units, :integer, null: false, default: 1
    add_check_constraint :agent_ai_executions, "consumption_units > 0", name: "agent_ai_positive_units"
    add_index :agent_ai_executions, %i[agent_workspace_id created_at]
  end
end
