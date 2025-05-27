# frozen_string_literal: true

class AddForeignKeysToAuditLogs < ActiveRecord::Migration[7.2]
  def change
    # 外部キー制約を安全に追加
    # adminsテーブルが作成済みであることを確認してから実行

    # 既存の外部キー制約が存在する場合は削除
    if foreign_key_exists?(:audit_logs, :admins)
      remove_foreign_key :audit_logs, :admins
    end

    # 新しい外部キー制約を追加
    # on_delete: :nullify により、管理者削除時にaudit_logsのuser_idをNULLに設定
    add_foreign_key :audit_logs, :admins, column: :user_id, on_delete: :nullify

    Rails.logger.info "Foreign key constraint added: audit_logs -> admins (user_id)"
  end

  def down
    # ロールバック時の処理
    if foreign_key_exists?(:audit_logs, :admins)
      remove_foreign_key :audit_logs, :admins
    end

    Rails.logger.info "Foreign key constraint removed: audit_logs -> admins (user_id)"
  end
end
