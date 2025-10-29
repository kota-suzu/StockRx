class ConvertToPolymorphicAssociationsInInterStoreTransfers < ActiveRecord::Migration[8.0]
  def up
    # ポリモーフィック関連付けのためのtypeカラムを追加
    add_column :inter_store_transfers, :requested_by_type, :string
    add_column :inter_store_transfers, :approved_by_type, :string

    # 不足している*_by_idカラムとtypeカラムを追加
    add_column :inter_store_transfers, :shipped_by_id, :integer
    add_column :inter_store_transfers, :shipped_by_type, :string
    add_column :inter_store_transfers, :completed_by_id, :integer
    add_column :inter_store_transfers, :completed_by_type, :string
    add_column :inter_store_transfers, :cancelled_by_id, :integer
    add_column :inter_store_transfers, :cancelled_by_type, :string

    # 既存データのtypeカラムを'Admin'に設定（メタ認知：既存データは管理者による作成と想定）
    execute <<-SQL
      UPDATE inter_store_transfers#{' '}
      SET requested_by_type = 'Admin'#{' '}
      WHERE requested_by_id IS NOT NULL
    SQL

    execute <<-SQL
      UPDATE inter_store_transfers#{' '}
      SET approved_by_type = 'Admin'#{' '}
      WHERE approved_by_id IS NOT NULL
    SQL

    # インデックスの追加（パフォーマンス最適化）
    add_index :inter_store_transfers, [ :requested_by_type, :requested_by_id ]
    add_index :inter_store_transfers, [ :approved_by_type, :approved_by_id ]
    add_index :inter_store_transfers, [ :shipped_by_type, :shipped_by_id ]
    add_index :inter_store_transfers, [ :completed_by_type, :completed_by_id ]
    add_index :inter_store_transfers, [ :cancelled_by_type, :cancelled_by_id ]
  end

  def down
    # インデックスの安全な削除（存在する場合のみ）
    connection.indexes(:inter_store_transfers).each do |index|
      if index.columns == %w[requested_by_type requested_by_id]
        remove_index :inter_store_transfers, [ :requested_by_type, :requested_by_id ]
      elsif index.columns == %w[approved_by_type approved_by_id]
        remove_index :inter_store_transfers, [ :approved_by_type, :approved_by_id ]
      elsif index.columns == %w[shipped_by_type shipped_by_id]
        remove_index :inter_store_transfers, [ :shipped_by_type, :shipped_by_id ]
      elsif index.columns == %w[completed_by_type completed_by_id]
        remove_index :inter_store_transfers, [ :completed_by_type, :completed_by_id ]
      elsif index.columns == %w[cancelled_by_type cancelled_by_id]
        remove_index :inter_store_transfers, [ :cancelled_by_type, :cancelled_by_id ]
      end
    end

    # カラムの安全な削除（存在する場合のみ）
    remove_column :inter_store_transfers, :requested_by_type if column_exists?(:inter_store_transfers, :requested_by_type)
    remove_column :inter_store_transfers, :approved_by_type if column_exists?(:inter_store_transfers, :approved_by_type)
    remove_column :inter_store_transfers, :shipped_by_id if column_exists?(:inter_store_transfers, :shipped_by_id)
    remove_column :inter_store_transfers, :shipped_by_type if column_exists?(:inter_store_transfers, :shipped_by_type)
    remove_column :inter_store_transfers, :completed_by_id if column_exists?(:inter_store_transfers, :completed_by_id)
    remove_column :inter_store_transfers, :completed_by_type if column_exists?(:inter_store_transfers, :completed_by_type)
    remove_column :inter_store_transfers, :cancelled_by_id if column_exists?(:inter_store_transfers, :cancelled_by_id)
    remove_column :inter_store_transfers, :cancelled_by_type if column_exists?(:inter_store_transfers, :cancelled_by_type)
  end
end
