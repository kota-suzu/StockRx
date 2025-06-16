class AddCounterCachesToStores < ActiveRecord::Migration[8.0]
  def change
    # Counter Cacheカラムを追加（デフォルト値0で初期化）
    add_column :stores, :store_inventories_count, :integer, default: 0, null: false
    add_column :stores, :pending_outgoing_transfers_count, :integer, default: 0, null: false
    add_column :stores, :pending_incoming_transfers_count, :integer, default: 0, null: false
    add_column :stores, :low_stock_items_count, :integer, default: 0, null: false

    # パフォーマンス向上のためのインデックス追加
    add_index :stores, :store_inventories_count
    add_index :stores, :low_stock_items_count

    # 既存データのCounter Cacheを初期化
    reversible do |dir|
      dir.up do
        Store.reset_counters_safely
      end
    end
  end
end
