class AddUserToInventoryLogs < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:inventory_logs, :admin_id)
      add_reference :inventory_logs, :admin, foreign_key: true
    end
  end
end
