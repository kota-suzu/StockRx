class AddUserToInventoryLogs < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:inventory_logs, :user_id)
      add_reference :inventory_logs, :user, foreign_key: false
    end
  end
end
