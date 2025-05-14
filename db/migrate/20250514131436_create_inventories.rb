class CreateInventories < ActiveRecord::Migration[7.2]
  def change
    create_table :inventories do |t|
      t.string :name, null: false
      t.integer :quantity, null: false, default: 0
      t.decimal :price, precision: 10, scale: 2, null: false, default: 0.0
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :inventories, :name
  end
end
