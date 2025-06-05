class RemoveUserFromInventoryLogs < ActiveRecord::Migration[8.0]
  def change
    remove_reference :inventory_logs, :user, foreign_key: false
  end
end
