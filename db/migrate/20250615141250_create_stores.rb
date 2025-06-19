class CreateStores < ActiveRecord::Migration[8.0]
  def change
    create_table :stores, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci" do |t|
      t.string :name, null: false, limit: 100, comment: "店舗名"
      t.string :code, null: false, limit: 20, comment: "店舗コード（一意識別子）"
      t.string :store_type, null: false, limit: 30, default: "pharmacy", comment: "店舗種別（pharmacy, warehouse, headquarters）"
      t.string :region, limit: 50, comment: "地域・エリア"
      t.text :address, comment: "住所"
      t.string :phone, limit: 20, comment: "電話番号"
      t.string :email, limit: 100, comment: "店舗メールアドレス"
      t.string :manager_name, limit: 50, comment: "店舗責任者名"
      t.boolean :active, default: true, null: false, comment: "店舗有効フラグ"

      t.timestamps
    end

    # インデックス追加（パフォーマンス最適化）
    add_index :stores, :code, unique: true, comment: "店舗コード一意制約"
    add_index :stores, :store_type, comment: "店舗種別による検索最適化"
    add_index :stores, :region, comment: "地域別検索最適化"
    add_index :stores, :active, comment: "有効店舗フィルタ最適化"
    add_index :stores, [ :store_type, :active ], comment: "種別・有効状態複合検索"
  end
end
