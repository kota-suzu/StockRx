class AddStoreFieldsToAdmins < ActiveRecord::Migration[8.0]
  def change
    # 店舗関連フィールド追加
    add_reference :admins, :store, foreign_key: { on_delete: :restrict }, comment: "所属店舗ID（本部管理者の場合はNULL）"
    add_column :admins, :role, :string, limit: 30, default: "store_user", null: false, comment: "管理者役割（headquarters_admin, store_manager, pharmacist, store_user）"
    add_column :admins, :name, :string, limit: 50, comment: "管理者名"
    add_column :admins, :active, :boolean, default: true, null: false, comment: "アカウント有効フラグ"

    # パフォーマンス最適化インデックス（add_referenceで自動作成されるstore_idは除外）
    add_index :admins, :role, comment: "役割別検索最適化"
    add_index :admins, [ :role, :active ], comment: "役割・有効状態複合検索"
    add_index :admins, [ :store_id, :role ], comment: "店舗・役割複合検索"
  end
end
