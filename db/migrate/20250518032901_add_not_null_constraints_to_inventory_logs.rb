class AddNotNullConstraintsToInventoryLogs < ActiveRecord::Migration[7.2]
  def change
    # 必須フィールドにNOT NULL制約を追加
    change_column_null :inventory_logs, :delta, false if column_exists?(:inventory_logs, :delta)
    change_column_null :inventory_logs, :operation_type, false if column_exists?(:inventory_logs, :operation_type)
    change_column_null :inventory_logs, :previous_quantity, false if column_exists?(:inventory_logs, :previous_quantity)
    change_column_null :inventory_logs, :current_quantity, false if column_exists?(:inventory_logs, :current_quantity)

    # インデックスが存在しない場合のみ追加
    unless index_exists?(:inventory_logs, :created_at)
      add_index :inventory_logs, :created_at  # 時系列検索用
    end

    unless index_exists?(:inventory_logs, :operation_type)
      add_index :inventory_logs, :operation_type  # 操作種別検索用
    end
  end
end
