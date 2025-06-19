class CreateStoreInventories < ActiveRecord::Migration[8.0]
  def change
    create_table :store_inventories, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.references :store, null: false, foreign_key: { on_delete: :cascade }, comment: "店舗ID"
      t.references :inventory, null: false, foreign_key: { on_delete: :cascade }, comment: "商品ID"
      t.integer :quantity, default: 0, null: false, comment: "現在在庫数"
      t.integer :reserved_quantity, default: 0, null: false, comment: "予約済み在庫数（移動申請中等）"
      t.integer :safety_stock_level, default: 5, null: false, comment: "安全在庫レベル（アラート閾値）"
      t.datetime :last_updated_at, comment: "最終在庫更新日時"

      t.timestamps
    end

    # 複合ユニーク制約（店舗・商品の組み合わせは一意）
    add_index :store_inventories, [ :store_id, :inventory_id ], unique: true, name: "uniq_store_inventory", comment: "店舗・商品組み合わせ一意制約"

    # パフォーマンス最適化インデックス（referencesで自動作成されるため、store_id, inventory_idは除外）
    add_index :store_inventories, [ :quantity, :safety_stock_level ], name: "idx_stock_levels", comment: "在庫レベル検索最適化"
    add_index :store_inventories, :last_updated_at, comment: "最終更新日時検索最適化"

    # 在庫アラート用インデックス（quantity <= safety_stock_level）
    add_index :store_inventories, [ :store_id, :quantity, :safety_stock_level ], name: "idx_low_stock_alert", comment: "低在庫アラート検索最適化"
  end
end
