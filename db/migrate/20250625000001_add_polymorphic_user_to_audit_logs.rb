# frozen_string_literal: true

class AddPolymorphicUserToAuditLogs < ActiveRecord::Migration[7.2]
  def change
    # user_typeカラムを追加してポリモーフィック関連にする
    add_column :audit_logs, :user_type, :string

    # 既存のuser_idをAdmin型として更新
    AuditLog.where.not(user_id: nil).update_all(user_type: 'Admin')

    # ポリモーフィック用のインデックスを追加
    add_index :audit_logs, [ :user_type, :user_id ]

    # 既存のuser_idインデックスは残す（後方互換性のため）
  end
end
