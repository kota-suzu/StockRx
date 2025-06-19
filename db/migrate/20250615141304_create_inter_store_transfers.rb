class CreateInterStoreTransfers < ActiveRecord::Migration[8.0]
  def change
    create_table :inter_store_transfers, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.bigint :source_store_id, null: false, comment: "移動元店舗ID"
      t.bigint :destination_store_id, null: false, comment: "移動先店舗ID"
      t.references :inventory, null: false, foreign_key: { on_delete: :cascade }, comment: "商品ID"
      t.integer :quantity, null: false, comment: "移動数量"
      t.integer :status, default: 0, null: false, comment: "移動ステータス（0:pending, 1:approved, 2:rejected, 3:in_transit, 4:completed, 5:cancelled）"
      t.integer :priority, default: 0, null: false, comment: "優先度（0:normal, 1:urgent, 2:emergency）"
      t.text :reason, comment: "移動理由・備考"
      t.bigint :requested_by_id, null: false, comment: "申請者（Admin ID）"
      t.bigint :approved_by_id, comment: "承認者（Admin ID）"
      t.datetime :requested_at, null: false, comment: "申請日時"
      t.datetime :approved_at, comment: "承認日時"
      t.datetime :completed_at, comment: "完了日時"

      t.timestamps
    end

    # Foreign key制約
    add_foreign_key :inter_store_transfers, :stores, column: :source_store_id, on_delete: :cascade
    add_foreign_key :inter_store_transfers, :stores, column: :destination_store_id, on_delete: :cascade
    add_foreign_key :inter_store_transfers, :admins, column: :requested_by_id, on_delete: :restrict
    add_foreign_key :inter_store_transfers, :admins, column: :approved_by_id, on_delete: :restrict

    # パフォーマンス最適化インデックス（referencesで自動作成されるinventory_idは除外）
    add_index :inter_store_transfers, :source_store_id, comment: "移動元店舗検索最適化"
    add_index :inter_store_transfers, :destination_store_id, comment: "移動先店舗検索最適化"
    add_index :inter_store_transfers, :status, comment: "ステータス別検索最適化"
    add_index :inter_store_transfers, [ :status, :priority ], comment: "ステータス・優先度複合検索"
    add_index :inter_store_transfers, :requested_by_id, comment: "申請者別検索最適化"
    add_index :inter_store_transfers, :approved_by_id, comment: "承認者別検索最適化"
    add_index :inter_store_transfers, :requested_at, comment: "申請日時検索最適化"
    add_index :inter_store_transfers, [ :source_store_id, :status, :requested_at ], name: "idx_source_status_date", comment: "店舗別ステータス・日時複合検索"

    # 業務ロジック制約
    add_check_constraint :inter_store_transfers, "quantity > 0", name: "chk_positive_quantity"
    add_check_constraint :inter_store_transfers, "source_store_id != destination_store_id", name: "chk_different_stores"
  end
end
