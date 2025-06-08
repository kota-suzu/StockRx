# frozen_string_literal: true

# マイグレーション実行履歴モデル
#
# CLAUDE.md準拠の設計:
# - SOLID原則適用
# - セキュリティバイデザイン
# - 可観測性確保
# - 横展開一貫性
class MigrationExecution < ApplicationRecord
  # ============================================
  # 関連性定義
  # ============================================

  # 実行者（監査ログ）
  belongs_to :admin, class_name: "Admin"

  # 進行状況ログ（1:N）
  has_many :migration_progress_logs, dependent: :destroy

  # ============================================
  # バリデーション（Defense in Depth）
  # ============================================

  # 必須フィールド
  validates :version, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :status, presence: true
  validates :admin_id, presence: true

  # ステータス値制限はenumで自動的に処理される

  # 数値範囲チェック
  validates :processed_records, :total_records,
            numericality: { greater_than_or_equal_to: 0 }
  validates :progress_percentage,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :retry_count,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }

  # 時刻整合性チェック
  validate :completed_at_after_started_at

  # JSON フィールドの構造検証
  validate :validate_configuration_structure
  validate :validate_rollback_data_structure

  # ============================================
  # Enum定義（型安全性向上）
  # ============================================

  enum :status, {
    pending: "pending",           # 実行待ち
    running: "running",           # 実行中
    completed: "completed",       # 完了
    failed: "failed",            # 失敗
    rolled_back: "rolled_back",  # ロールバック済み
    paused: "paused",            # 一時停止
    cancelled: "cancelled"        # キャンセル
  }

  # ============================================
  # スコープ定義（クエリ最適化）
  # ============================================

  # ステータス別
  scope :active, -> { where(status: %w[pending running paused]) }
  scope :completed_or_failed, -> { where(status: %w[completed failed rolled_back cancelled]) }

  # 時系列
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where(created_at: Date.current.beginning_of_day..Date.current.end_of_day) }
  scope :this_week, -> { where(created_at: 1.week.ago..Time.current) }

  # 実行者別
  scope :by_admin, ->(admin) { where(admin: admin) }

  # 進行状況別
  scope :in_progress, -> { where("progress_percentage < 100 AND status IN (?)", %w[running paused]) }
  scope :stalled, -> { where("updated_at < ? AND status = ?", 10.minutes.ago, "running") }

  # ============================================
  # コールバック（ライフサイクル管理）
  # ============================================

  before_validation :set_defaults, on: :create
  before_save :update_progress_percentage
  before_save :set_system_info, if: :new_record?
  after_update :broadcast_status_change, if: :saved_change_to_status?

  # ============================================
  # ビジネスロジック
  # ============================================

  # 実行可能性チェック
  def can_execute?
    pending? && migration_exists?
  end

  # 一時停止可能性チェック
  def can_pause?
    running?
  end

  # ロールバック可能性チェック
  def can_rollback?
    completed? && rollback_data.present?
  end

  # キャンセル可能性チェック
  def can_cancel?
    %w[pending running paused].include?(status)
  end

  # 実行時間計算
  def execution_duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  # 推定完了時刻
  def estimated_completion_time
    return nil unless started_at && running? && progress_percentage > 0

    elapsed = Time.current - started_at
    estimated_total = elapsed * (100.0 / progress_percentage)
    started_at + estimated_total
  end

  # 平均処理速度（レコード/秒）
  def average_records_per_second
    return 0 unless started_at && processed_records > 0

    elapsed = (completed_at || Time.current) - started_at
    return 0 if elapsed <= 0

    (processed_records.to_f / elapsed).round(10)
  end

  # 最新の進行状況ログ
  def latest_progress_log
    migration_progress_logs.order(:created_at).last
  end

  # システムメトリクス取得
  def current_system_metrics
    latest_progress_log&.metrics || {}
  end

  # エラー情報の構造化
  def structured_error_info
    return nil unless error_message.present?

    {
      message: error_message,
      backtrace: error_backtrace&.split("\n"),
      retry_count: retry_count,
      occurred_at: updated_at,
      phase: latest_progress_log&.phase
    }
  end

  # ============================================
  # アクション実行メソッド
  # ============================================

  # 実行開始
  def start_execution!
    return false unless can_execute?

    transaction do
      update!(
        status: "running",
        started_at: Time.current,
        hostname: Socket.gethostname,
        process_id: Process.pid
      )

      # 初期進行状況ログ
      migration_progress_logs.create!(
        phase: "initialization",
        progress_percentage: 0,
        message: "マイグレーション実行を開始しました",
        log_level: "info"
      )
    end

    true
  rescue => e
    Rails.logger.error "Failed to start migration execution: #{e.message}"
    false
  end

  # 完了マーク
  def mark_completed!
    update!(
      status: "completed",
      completed_at: Time.current,
      processed_records: total_records || processed_records,
      progress_percentage: 100.0
    )
  end

  # 失敗マーク
  def mark_failed!(error_info)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: error_info[:message],
      error_backtrace: error_info[:backtrace]&.join("\n"),
      retry_count: retry_count + 1
    )
  end

  # 一時停止
  def pause!
    return false unless can_pause?
    update!(status: "paused")
  end

  # 再開
  def resume!
    return false unless paused?
    update!(status: "running")
  end

  private

  # ============================================
  # プライベートメソッド
  # ============================================

  def set_defaults
    self.environment ||= Rails.env
    self.configuration ||= {}
    self.metrics ||= {}
  end

  def update_progress_percentage
    return unless processed_records && total_records && total_records > 0

    self.progress_percentage = [ (processed_records.to_f / total_records * 100), 100.0 ].min.round(2)
  end

  def set_system_info
    self.hostname ||= Socket.gethostname
    self.process_id ||= Process.pid
  end

  def completed_at_after_started_at
    return unless started_at && completed_at

    if completed_at < started_at
      errors.add(:completed_at, "は開始時刻より後である必要があります")
    end
  end

  def validate_configuration_structure
    return unless configuration.present?

    required_keys = %w[batch_size cpu_threshold memory_threshold]
    missing_keys = required_keys - configuration.keys

    if missing_keys.any?
      errors.add(:configuration, "必須キーが不足しています: #{missing_keys.join(', ')}")
    end
  end

  def validate_rollback_data_structure
    return unless rollback_data.present?

    unless rollback_data.is_a?(Array)
      errors.add(:rollback_data, "は配列である必要があります")
    end
  end

  def migration_exists?
    # TODO: 実際のマイグレーションファイルの存在確認
    # ActiveRecord::Migration.get_all_versions.include?(version)
    true
  end

  def broadcast_status_change
    # TODO: ActionCable統合での状態変更通知
    # MigrationStatusChannel.broadcast_to(
    #   self,
    #   {
    #     status: status,
    #     updated_at: updated_at,
    #     progress_percentage: progress_percentage
    #   }
    # )
  end
end

# ============================================
# 設計ノート（継続的改善）
# ============================================

# 1. パフォーマンス最適化
#    - インデックスの効果測定
#    - N+1クエリの継続監視
#    - JSON フィールドのクエリ最適化

# 2. セキュリティ強化
#    - 機密情報のマスキング実装
#    - アクセス制御の強化
#    - 監査ログの詳細化

# 3. 可観測性向上
#    - メトリクス収集の自動化
#    - アラート条件の精緻化
#    - ダッシュボード連携

# TODO: 次期実装
# - [HIGH] ActionCable統合
# - [MEDIUM] メトリクス自動収集
# - [MEDIUM] アラート機能
# - [LOW] 機械学習による異常検知
