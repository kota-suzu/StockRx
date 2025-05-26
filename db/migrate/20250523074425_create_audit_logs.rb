# frozen_string_literal: true

class CreateAuditLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :audit_logs do |t|
      # ポリモーフィック関連
      t.references :auditable, polymorphic: true, null: false, index: true

      # ユーザー関連（外部キー制約は後で追加）
      t.bigint :user_id, null: true

      # 監査情報
      t.string :action, null: false
      t.text :message, null: false
      t.text :details

      # リクエスト情報
      t.string :ip_address
      t.text :user_agent

      # 操作情報
      t.string :operation_source
      t.string :operation_type

      t.timestamps
    end

    # インデックス
    add_index :audit_logs, :user_id
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at
    add_index :audit_logs, [ :auditable_type, :auditable_id ]

    # TODO: 外部キー制約は別のマイグレーションで追加
    # 理由：adminsテーブルとの循環依存を回避し、安全なデータベース再構築を可能にする
    # 実装予定：db/migrate/add_foreign_keys_to_audit_logs.rb
    # add_foreign_key :audit_logs, :admins, column: :user_id, on_delete: :nullify
  end
end
