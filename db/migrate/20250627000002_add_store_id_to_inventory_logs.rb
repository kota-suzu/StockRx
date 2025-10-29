class AddStoreIdToInventoryLogs < ActiveRecord::Migration[8.0]
  def change
    # 店舗IDを追加（どの店舗での操作かを記録）
    add_reference :inventory_logs, :store, null: true, foreign_key: true, comment: "操作が行われた店舗"

    # notesカラムを追加（noteカラムが既に存在する場合は別名で）
    unless column_exists?(:inventory_logs, :notes)
      add_column :inventory_logs, :notes, :text, comment: "操作に関する備考"
    end

    # インデックス追加
    add_index :inventory_logs, [ :store_id, :created_at ], name: 'idx_store_logs'
  end
end
