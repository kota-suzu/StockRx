class CreateBatchMovements < ActiveRecord::Migration[8.0]
  def change
    create_table :batch_movements do |t|
      t.references :batch, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.integer :quantity, null: false, comment: "移動数量"
      t.date :movement_date, null: false, comment: "移動日"
      t.text :notes, comment: "備考"
      t.references :store_inventory, foreign_key: true, comment: "店舗在庫への関連"

      t.timestamps
    end

    add_index :batch_movements, :movement_date
    add_index :batch_movements, [ :batch_id, :store_id, :movement_date ], name: "idx_batch_store_movement"
  end
end
