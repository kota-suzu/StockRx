class AddShipmentsAndReceiptsCountToInventories < ActiveRecord::Migration[8.0]
  def up
    # Counter cache用のカラムを追加
    add_column :inventories, :shipments_count, :integer, default: 0, null: false
    add_column :inventories, :receipts_count, :integer, default: 0, null: false

    # パフォーマンス向上のためインデックスを追加
    add_index :inventories, :shipments_count
    add_index :inventories, :receipts_count

    # 既存データのカウントを同期
    reversible do |dir|
      dir.up do
        # Shipmentsカウントの同期
        execute <<-SQL.squish
          UPDATE inventories#{' '}
          SET shipments_count = (
            SELECT COUNT(*)#{' '}
            FROM shipments#{' '}
            WHERE shipments.inventory_id = inventories.id
          )
        SQL

        # Receiptsカウントの同期
        execute <<-SQL.squish
          UPDATE inventories#{' '}
          SET receipts_count = (
            SELECT COUNT(*)#{' '}
            FROM receipts#{' '}
            WHERE receipts.inventory_id = inventories.id
          )
        SQL
      end
    end
  end

  def down
    remove_index :inventories, :shipments_count
    remove_index :inventories, :receipts_count
    remove_column :inventories, :shipments_count
    remove_column :inventories, :receipts_count
  end
end
