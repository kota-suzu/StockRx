class AddInventoryLogsCountToInventories < ActiveRecord::Migration[8.0]
  def up
    # Counter cache用のカラムを追加
    add_column :inventories, :inventory_logs_count, :integer, default: 0, null: false

    # パフォーマンス向上のためインデックスを追加
    add_index :inventories, :inventory_logs_count

    # 既存データのカウントを同期
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE inventories#{' '}
          SET inventory_logs_count = (
            SELECT COUNT(*)#{' '}
            FROM inventory_logs#{' '}
            WHERE inventory_logs.inventory_id = inventories.id
          )
        SQL
      end
    end
  end

  def down
    remove_index :inventories, :inventory_logs_count
    remove_column :inventories, :inventory_logs_count
  end
end
