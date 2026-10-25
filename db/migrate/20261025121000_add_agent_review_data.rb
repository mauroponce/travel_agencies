class AddAgentReviewData < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_import_items, :review_data, :jsonb, null: false, default: {}
  end
end
