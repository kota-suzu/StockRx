# frozen_string_literal: true

# 🔐 セキュリティ強化: TempPasswordsテーブルへのセキュリティフィールド追加
# Phase 1緊急対応: ブルートフォース攻撃対策と監査機能強化
class AddSecurityFieldsToTempPasswords < ActiveRecord::Migration[8.0]
  def change
    # アクティブ状態管理（管理者による無効化対応）
    add_column :temp_passwords, :active, :boolean, default: true, null: false, 
               comment: "アクティブ状態（管理者による無効化可能）"
    
    # ブルートフォース攻撃対策
    add_column :temp_passwords, :usage_attempts, :integer, default: 0, null: false, 
               comment: "使用試行回数（ブルートフォース対策）"
    add_column :temp_passwords, :last_attempt_at, :datetime, 
               comment: "最終使用試行日時"
    
    # 監査ログ用管理者ID
    add_column :temp_passwords, :generated_by_admin_id, :string, 
               comment: "生成実行管理者ID（監査用）"

    # セキュリティ関連インデックス（存在確認付き安全な追加）
    add_index :temp_passwords, :active, name: "index_temp_passwords_on_active" unless index_exists?(:temp_passwords, :active)
    add_index :temp_passwords, :usage_attempts, name: "index_temp_passwords_on_usage_attempts" unless index_exists?(:temp_passwords, :usage_attempts)
    add_index :temp_passwords, :last_attempt_at, name: "index_temp_passwords_on_last_attempt_at" unless index_exists?(:temp_passwords, :last_attempt_at)
    
    # セキュリティ監査用複合インデックス
    unless index_exists?(:temp_passwords, [:generated_by_admin_id, :created_at])
      add_index :temp_passwords, [:generated_by_admin_id, :created_at], 
                name: "index_temp_passwords_on_admin_created_at"
    end
    
    # 複合インデックス（アクティブな有効期限内パスワード検索用）
    unless index_exists?(:temp_passwords, [:store_user_id, :active, :expires_at])
      add_index :temp_passwords, [:store_user_id, :active, :expires_at], 
                where: "active = true AND expires_at > NOW()",
                name: "index_temp_passwords_active_valid"
    end

    # NOT NULL制約の安全な追加
    change_column_null :temp_passwords, :password_hash, false if column_exists?(:temp_passwords, :password_hash)
    change_column_null :temp_passwords, :expires_at, false if column_exists?(:temp_passwords, :expires_at)

    # 既存データの初期化（安全な更新）
    reversible do |dir|
      dir.up do
        # 既存の一時パスワードをアクティブ状態に設定
        execute <<-SQL
          UPDATE temp_passwords#{' '}
          SET active = true, usage_attempts = 0#{' '}
          WHERE active IS NULL OR usage_attempts IS NULL
        SQL
        
        Rails.logger.info "🔐 Security fields added to TempPasswords table"
        Rails.logger.info "   - Active status management enabled"
        Rails.logger.info "   - Brute-force protection counters added"
        Rails.logger.info "   - Enhanced audit logging ready"
      end
    end
  end
end
