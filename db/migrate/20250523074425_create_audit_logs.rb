class CreateAuditLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :audit_logs do |t|
      # ポリモーフィック関連
      t.references :auditable, polymorphic: true, null: false, index: true

      # ユーザー関連
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

    # 外部キー制約
    add_foreign_key :audit_logs, :admins, column: :user_id, on_delete: :nullify
  end
end
