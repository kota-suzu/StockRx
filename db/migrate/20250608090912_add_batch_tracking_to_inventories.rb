class AddBatchTrackingToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :batch_tracking_enabled, :boolean
    add_column :inventories, :batch_number_required, :boolean
    add_column :inventories, :expiry_date_required, :boolean
  end
end
