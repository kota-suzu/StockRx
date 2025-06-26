# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Change unit column from string to integer for enum support
    # First set default values for existing records
    reversible do |dir|
      dir.up do
        # Map existing string values to integers
        execute <<-SQL
          UPDATE inventories 
          SET unit = CASE 
            WHEN unit = 'piece' THEN 0
            WHEN unit = 'box' THEN 1
            WHEN unit = 'bottle' THEN 2
            WHEN unit = 'pack' THEN 3
            WHEN unit = 'kg' THEN 4
            WHEN unit = 'g' THEN 5
            WHEN unit = 'l' THEN 6
            WHEN unit = 'ml' THEN 7
            ELSE 0
          END
        SQL
        
        # Change column type to integer
        change_column :inventories, :unit, :integer, default: 0, null: false
      end
      
      dir.down do
        # Change back to string and restore original values
        change_column :inventories, :unit, :string, null: true
        
        execute <<-SQL
          UPDATE inventories 
          SET unit = CASE 
            WHEN unit = 0 THEN 'piece'
            WHEN unit = 1 THEN 'box'
            WHEN unit = 2 THEN 'bottle'
            WHEN unit = 3 THEN 'pack'
            WHEN unit = 4 THEN 'kg'
            WHEN unit = 5 THEN 'g'
            WHEN unit = 6 THEN 'l'
            WHEN unit = 7 THEN 'ml'
            ELSE 'piece'
          END
        SQL
      end
    end
    
    # Add performance indexes
    add_index :inventories, :unit, comment: "Unit type search optimization"
    add_index :store_inventories, [:quantity, :safety_stock_level, :reserved_quantity], 
              name: 'idx_store_inv_stock_analysis', 
              comment: "Store inventory analysis optimization"
    add_index :inter_store_transfers, [:status, :priority, :requested_at], 
              name: 'idx_transfers_priority_queue',
              comment: "Transfer queue processing optimization"
    add_index :batches, [:expires_on, :quantity], 
              name: 'idx_batches_expiry_stock',
              comment: "Expiring inventory tracking optimization"
  end
end