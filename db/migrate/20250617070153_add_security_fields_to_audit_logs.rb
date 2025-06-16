# frozen_string_literal: true

# Phase 5-2: 監査ログのセキュリティ機能強化
class AddSecurityFieldsToAuditLogs < ActiveRecord::Migration[8.0]
  def change
    # セキュリティ関連フィールドの追加
    add_column :audit_logs, :severity, :string, comment: "イベントの重要度 (info, warning, critical)"
    add_column :audit_logs, :security_event, :boolean, default: false, comment: "セキュリティイベントフラグ"
    add_column :audit_logs, :session_id, :string, comment: "セッションID"
    
    # インデックスの追加
    add_index :audit_logs, :severity
    add_index :audit_logs, :security_event
    add_index :audit_logs, [:action, :created_at], name: "index_audit_logs_on_action_and_created_at"
    add_index :audit_logs, [:user_id, :created_at], name: "index_audit_logs_on_user_id_and_created_at"
    
    # 既存データの更新
    reversible do |dir|
      dir.up do
        # セキュリティ関連アクションの severity 設定
        execute <<-SQL
          UPDATE audit_logs 
          SET security_event = true, 
              severity = CASE
                WHEN action IN ('security_event', 'failed_login') THEN 'warning'
                WHEN action IN ('permission_change', 'password_change') THEN 'critical'
                WHEN action IN ('login', 'logout') THEN 'info'
                ELSE 'info'
              END
          WHERE action IN ('security_event', 'failed_login', 'permission_change', 
                          'password_change', 'login', 'logout')
        SQL
      end
    end
  end
end