class CreateInventoryLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :inventory_logs do |t|
      t.references :inventory, null: false, foreign_key: true
      t.integer :delta
      t.string :operation_type
      t.integer :previous_quantity
      t.integer :current_quantity
      t.text :note

      t.timestamps
    end
  end
end
