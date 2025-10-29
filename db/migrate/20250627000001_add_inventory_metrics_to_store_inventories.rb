class AddInventoryMetricsToStoreInventories < ActiveRecord::Migration[8.0]
  def change
    # 日次使用量レート（需要予測に使用）
    add_column :store_inventories, :daily_usage_rate, :decimal, precision: 10, scale: 2, default: 0.0, comment: "推定日次使用量"

    # 最大在庫レベル（発注数量計算に使用）
    add_column :store_inventories, :max_stock_level, :integer, comment: "最大在庫レベル"

    # リードタイム（発注から到着までの日数）
    add_column :store_inventories, :lead_time_days, :integer, default: 7, comment: "リードタイム（日数）"

    # インデックス追加
    add_index :store_inventories, :daily_usage_rate
    add_index :store_inventories, [ :quantity, :reorder_level ], name: 'idx_reorder_check'
  end
end
