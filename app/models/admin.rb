# frozen_string_literal: true

class Admin < ApplicationRecord
  include Auditable

  # :database_authenticatable = メール・パスワード認証
  # :recoverable = パスワードリセット
  # :rememberable = ログイン状態記憶
  # :validatable = メールとパスワードのバリデーション
  # :lockable = ログイン試行回数制限・ロック
  # :timeoutable = 一定時間操作がないセッションをタイムアウト
  # :trackable = ログイン履歴を記録
  devise :database_authenticatable, :recoverable, :rememberable,
         :validatable, :lockable, :timeoutable, :trackable

  # Deviseのデフォルトバリデーション（:validatable）に加えて
  # 独自のパスワード強度チェックを追加
  validates :password, password_strength: true, if: :password_required?

  # ============================================
  # 関連性定義（マイグレーション管理機能）
  # ============================================

  # マイグレーション実行履歴（1:N）
  has_many :migration_executions, dependent: :destroy

  # 最近の実行履歴（監査用）
  has_many :recent_migration_executions, -> { order(created_at: :desc).limit(10) },
           class_name: "MigrationExecution"

  # 失敗した実行履歴（トラブルシューティング用）
  has_many :failed_migration_executions, -> { where(status: "failed") },
           class_name: "MigrationExecution"

  # ============================================
  # マイグレーション管理用メソッド
  # ============================================

  # マイグレーション実行権限チェック
  def can_execute_migrations?
    # TODO: 権限レベル実装後に詳細化
    # super_admin? || has_migration_permission?
    true
  end

  # マイグレーション監視権限チェック
  def can_monitor_migrations?
    # TODO: 権限レベル実装後に詳細化
    true
  end

  # 実行統計情報
  def migration_execution_stats
    {
      total_executions: migration_executions.count,
      successful_executions: migration_executions.status_completed.count,
      failed_executions: migration_executions.status_failed.count,
      total_duration: migration_executions.sum(&:execution_duration),
      last_execution_at: migration_executions.maximum(:completed_at)
    }
  end

  # TODO: 認証・認可関連機能
  # 1. ユーザーモデルの実装（一般スタッフ向け）
  #    - Userモデルの作成と権限管理
  #    - 管理者によるユーザーアカウント管理機能
  # 2. 管理者権限レベルの実装
  #    - admin/super_admin権限区分の追加
  #    - 画面アクセス制御の詳細化
  #    - マイグレーション実行権限の詳細化
  # 3. 2要素認証の導入
  #    - devise-two-factor gemを利用
  #    - QRコード生成とTOTPワンタイムパスワード

  private

  # パスワードが必要なケースかどうかを判定
  # Devise内部の同名メソッドをオーバーライド
  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end
end
