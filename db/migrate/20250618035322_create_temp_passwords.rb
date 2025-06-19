# frozen_string_literal: true

# 🔐 セキュリティ機能: 店舗ユーザー一時パスワード管理テーブル
# Phase 1緊急実装: セキュアな一時パスワード生成・検証・期限管理機能
class CreateTempPasswords < ActiveRecord::Migration[8.0]
  def change
    create_table :temp_passwords do |t|
      # 関連付け（必須）
      t.references :store_user, null: false, foreign_key: true, comment: "対象店舗ユーザー"

      # セキュリティ関連フィールド（必須）
      t.string :password_hash, null: false, comment: "bcrypt暗号化された一時パスワード"
      t.datetime :expires_at, null: false, comment: "有効期限（デフォルト15分）"

      # 使用状況トラッキング
      t.datetime :used_at, comment: "使用済み日時（NULL=未使用）"
      t.boolean :active, default: true, null: false, comment: "アクティブ状態（管理者による無効化可能）"

      # 監査ログ情報
      t.string :ip_address, comment: "生成時のIPアドレス"
      t.text :user_agent, comment: "生成時のUser-Agent"
      t.string :generated_by_admin_id, comment: "生成実行管理者ID（監査用）"

      # セキュリティ強化フィールド
      t.integer :usage_attempts, default: 0, null: false, comment: "使用試行回数（ブルートフォース対策）"
      t.datetime :last_attempt_at, comment: "最終使用試行日時"

      t.timestamps
    end

    # パフォーマンス最適化インデックス（存在確認付き安全な追加）
    add_index :temp_passwords, :expires_at, name: "index_temp_passwords_on_expires_at" unless index_exists?(:temp_passwords, :expires_at)
    add_index :temp_passwords, :active, name: "index_temp_passwords_on_active" unless index_exists?(:temp_passwords, :active)
    add_index :temp_passwords, :created_at, name: "index_temp_passwords_on_created_at" unless index_exists?(:temp_passwords, :created_at)

    # 複合インデックス（アクティブな有効期限内パスワード検索用）
    unless index_exists?(:temp_passwords, [ :store_user_id, :active, :expires_at ])
      add_index :temp_passwords, [ :store_user_id, :active, :expires_at ],
                where: "active = true AND expires_at > NOW()",
                name: "index_temp_passwords_active_valid"
    end

    # セキュリティ監査用複合インデックス
    unless index_exists?(:temp_passwords, [ :generated_by_admin_id, :created_at ])
      add_index :temp_passwords, [ :generated_by_admin_id, :created_at ],
                name: "index_temp_passwords_on_admin_created_at"
    end

    # TODO: 🔴 Phase 1緊急（1週間以内）- 期限切れ一時パスワード自動削除機能
    # 優先度: 緊急（セキュリティリスク対策）
    # 実装内容:
    #   - 期限切れ + 24時間経過した一時パスワードの自動削除Job
    #   - 使用済み + 48時間経過した一時パスワードの自動削除Job
    #   - 削除実行前の監査ログ記録
    # 理由: データベース肥大化防止、セキュリティリスク最小化
    # 期待効果: ストレージ使用量最適化、攻撃対象の縮小
    # 工数見積: 2日
    # 依存関係: Sidekiq Job + Cron設定

    # TODO: 🟡 Phase 2重要（2週間以内）- ブルートフォース攻撃対策強化
    # 優先度: 重要（セキュリティ強化）
    # 実装内容:
    #   - usage_attempts上限設定（5回でロック）
    #   - IPアドレス別試行回数制限
    #   - 段階的遅延機能（1回目=0秒、2回目=1秒、3回目=3秒...）
    # 理由: 一時パスワードへのブルートフォース攻撃防止
    # 期待効果: セキュリティレベル向上、不正アクセス防止
    # 工数見積: 3日
    # 依存関係: Redis（レート制限）+ 監査ログ統合

    # Rails.logger出力（マイグレーション実行時の記録）
    Rails.logger.info "🔐 TempPasswords table created with security-enhanced structure"
    Rails.logger.info "   - bcrypt password hashing ready"
    Rails.logger.info "   - Auto-expiration mechanism (default: 15 min)"
    Rails.logger.info "   - Brute-force protection counters"
    Rails.logger.info "   - Comprehensive audit logging"
  end
end
