class RemoveForeignKeyConstraintsFromInterStoreTransfers < ActiveRecord::Migration[8.0]
  def up
    # ポリモーフィック関連付けのために古い外部キー制約を削除
    # メタ認知: AdminsテーブルへのFK制約がStoreUserの参照を阻んでいる
    
    # 既存の外部キー制約を確認して削除
    if foreign_key_exists?(:inter_store_transfers, :admins, column: :requested_by_id)
      remove_foreign_key :inter_store_transfers, :admins, column: :requested_by_id
    end
    
    if foreign_key_exists?(:inter_store_transfers, :admins, column: :approved_by_id)
      remove_foreign_key :inter_store_transfers, :admins, column: :approved_by_id
    end
    
    # 追加カラムの外部キー制約も削除（存在する場合）
    if foreign_key_exists?(:inter_store_transfers, :admins, column: :shipped_by_id)
      remove_foreign_key :inter_store_transfers, :admins, column: :shipped_by_id
    end
    
    if foreign_key_exists?(:inter_store_transfers, :admins, column: :completed_by_id)
      remove_foreign_key :inter_store_transfers, :admins, column: :completed_by_id
    end
    
    if foreign_key_exists?(:inter_store_transfers, :admins, column: :cancelled_by_id)
      remove_foreign_key :inter_store_transfers, :admins, column: :cancelled_by_id
    end
  end

  def down
    # ポリモーフィック関連付けを元に戻す場合、Admin専用の外部キー制約を復元
    # 注意: この操作はStoreUserデータがある場合は失敗する
    add_foreign_key :inter_store_transfers, :admins, column: :requested_by_id
    add_foreign_key :inter_store_transfers, :admins, column: :approved_by_id
    
    # 注意: 以下は元々存在しなかった可能性があるため、コメントアウト
    # add_foreign_key :inter_store_transfers, :admins, column: :shipped_by_id
    # add_foreign_key :inter_store_transfers, :admins, column: :completed_by_id
    # add_foreign_key :inter_store_transfers, :admins, column: :cancelled_by_id
  end
end
