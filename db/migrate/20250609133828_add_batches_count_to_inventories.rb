class AddBatchesCountToInventories < ActiveRecord::Migration[8.0]
  def up
    # Counter cache用のカラムを追加
    add_column :inventories, :batches_count, :integer, default: 0, null: false

    # パフォーマンス向上のためインデックスを追加
    add_index :inventories, :batches_count

    # 既存データのカウントを同期
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE inventories#{' '}
          SET batches_count = (
            SELECT COUNT(*)#{' '}
            FROM batches#{' '}
            WHERE batches.inventory_id = inventories.id
          )
        SQL
      end
    end
  end

  def down
    remove_index :inventories, :batches_count
    remove_column :inventories, :batches_count
  end
end
