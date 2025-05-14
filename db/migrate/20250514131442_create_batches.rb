class CreateBatches < ActiveRecord::Migration[7.2]
  def change
    create_table :batches do |t|
      t.references :inventory, null: false
      t.string :lot_code, null: false
      t.date :expires_on
      t.integer :quantity, null: false, default: 0

      t.timestamps
    end

    # 外部キー制約（ON DELETE CASCADE追加）
    add_foreign_key :batches, :inventories, on_delete: :cascade

    # 期限切れ日付の検索用インデックス
    add_index :batches, :expires_on

    # inventory_idとlot_codeの複合ユニーク制約
    add_index :batches, [ :inventory_id, :lot_code ], unique: true, name: 'uniq_inventory_lot'
  end
end
