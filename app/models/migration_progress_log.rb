# frozen_string_literal: true

# マイグレーション進行状況ログモデル
#
# CLAUDE.md準拠の設計:
# - 高頻度インサート最適化
# - リアルタイム監視対応
# - ActionCable統合準備
class MigrationProgressLog < ApplicationRecord
  # ============================================
  # 関連性定義
  # ============================================

  # 親のマイグレーション実行
  belongs_to :migration_execution, class_name: "MigrationExecution"

  # ============================================
  # バリデーション
  # ============================================

  # 必須フィールド
  validates :migration_execution_id, presence: true
  validates :phase, presence: true, length: { maximum: 100 }
  validates :progress_percentage, presence: true
  validates :log_level, presence: true

  # 数値範囲チェック
  validates :progress_percentage,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :processed_records,
            numericality: { greater_than_or_equal_to: 0 }
  validates :current_batch_size, :current_batch_number,
            numericality: { greater_than_or_equal_to: 1 },
            allow_nil: true
  validates :records_per_second, :estimated_remaining_seconds,
            numericality: { greater_than_or_equal_to: 0 },
            allow_nil: true

  # ログレベル制限
  validates :log_level, inclusion: {
    in: %w[debug info warn error fatal],
    message: "%{value}は有効なログレベルではありません"
  }

  # フェーズ値制限
  validates :phase, inclusion: {
    in: %w[initialization schema_change data_migration index_creation validation cleanup rollback],
    message: "%{value}は有効なフェーズではありません"
  }

  # JSON構造検証
  validate :validate_metrics_structure

  # ============================================
  # Enum定義
  # ============================================

  enum log_level: {
    debug: "debug",
    info: "info",
    warn: "warn",
    error: "error",
    fatal: "fatal"
  }, _prefix: true

  enum phase: {
    initialization: "initialization",      # 初期化
    schema_change: "schema_change",        # スキーマ変更
    data_migration: "data_migration",      # データ移行
    index_creation: "index_creation",      # インデックス作成
    validation: "validation",              # 検証
    cleanup: "cleanup",                    # クリーンアップ
    rollback: "rollback"                   # ロールバック
  }, _prefix: true

  # ============================================
  # スコープ定義
  # ============================================

  # 時系列順
  scope :chronological, -> { order(:created_at) }
  scope :reverse_chronological, -> { order(created_at: :desc) }

  # ログレベル別
  scope :errors_and_fatals, -> { where(log_level: %w[error fatal]) }
  scope :warnings_and_above, -> { where(log_level: %w[warn error fatal]) }

  # フェーズ別
  scope :by_phase, ->(phase_name) { where(phase: phase_name) }

  # 時間範囲
  scope :recent, ->(minutes = 30) { where("created_at > ?", minutes.minutes.ago) }
  scope :between, ->(start_time, end_time) { where(created_at: start_time..end_time) }

  # ActionCable関連
  scope :not_broadcasted, -> { where(broadcasted: false) }
  scope :broadcasted, -> { where(broadcasted: true) }

  # パフォーマンス分析用
  scope :with_performance_data, -> { where.not(records_per_second: nil) }
  scope :slow_batches, ->(threshold = 100) { where("records_per_second < ?", threshold) }

  # ============================================
  # コールバック
  # ============================================

  before_validation :set_defaults, on: :create
  after_create :update_parent_progress
  after_create :schedule_broadcast, if: :should_broadcast?

  # ============================================
  # ビジネスロジック
  # ============================================

  # フォーマット済みメッセージ
  def formatted_message
    timestamp = created_at.strftime("%H:%M:%S")
    level_indicator = log_level_indicator
    phase_indicator = "[#{phase.humanize}]"

    "#{timestamp} #{level_indicator} #{phase_indicator} #{message}"
  end

  # ログレベルインジケーター
  def log_level_indicator
    case log_level
    when "debug" then "🔍"
    when "info"  then "ℹ️"
    when "warn"  then "⚠️"
    when "error" then "❌"
    when "fatal" then "💀"
    else "📝"
    end
  end

  # システムメトリクス取得
  def cpu_usage
    metrics&.dig("cpu_usage")
  end

  def memory_usage
    metrics&.dig("memory_usage")
  end

  def db_connections
    metrics&.dig("db_connections")
  end

  def query_time
    metrics&.dig("query_time")
  end

  # 性能指標
  def performance_summary
    {
      records_per_second: records_per_second,
      batch_size: current_batch_size,
      cpu_usage: cpu_usage,
      memory_usage: memory_usage,
      efficiency_score: calculate_efficiency_score
    }
  end

  # 効率性スコア計算（0-100）
  def calculate_efficiency_score
    return nil unless records_per_second && cpu_usage && memory_usage

    # 基準値に対する相対的な効率性
    base_rps = 1000.0  # 基準: 1000レコード/秒
    cpu_penalty = [ cpu_usage - 50, 0 ].max * 0.5  # CPU50%超過でペナルティ
    memory_penalty = [ memory_usage - 70, 0 ].max * 0.3  # メモリ70%超過でペナルティ

    score = (records_per_second / base_rps * 100) - cpu_penalty - memory_penalty
    [ score, 0 ].max.round(1)
  end

  # アラート判定
  def requires_alert?
    log_level_error? || log_level_fatal? ||
    (cpu_usage && cpu_usage > 90) ||
    (memory_usage && memory_usage > 95) ||
    (records_per_second && records_per_second < 10)
  end

  # ActionCable配信用データ
  def broadcast_data
    {
      id: id,
      migration_execution_id: migration_execution_id,
      phase: phase,
      progress_percentage: progress_percentage,
      processed_records: processed_records,
      message: message,
      log_level: log_level,
      timestamp: created_at.iso8601,
      performance: performance_summary,
      system_metrics: metrics || {}
    }
  end

  # ============================================
  # クラスメソッド
  # ============================================

  # ログエントリ作成（ファクトリーメソッド）
  def self.create_log_entry(execution, phase, progress, message, level: "info", **options)
    create!(
      migration_execution: execution,
      phase: phase,
      progress_percentage: progress,
      message: message,
      log_level: level,
      processed_records: options[:processed_records],
      current_batch_size: options[:batch_size],
      current_batch_number: options[:batch_number],
      records_per_second: options[:records_per_second],
      estimated_remaining_seconds: options[:estimated_remaining],
      metrics: options[:metrics] || {}
    )
  end

  # 特定実行の進行状況サマリー
  def self.progress_summary_for(migration_execution)
    logs = where(migration_execution: migration_execution).chronological

    {
      total_logs: logs.count,
      error_count: logs.errors_and_fatals.count,
      warning_count: logs.log_level_warn.count,
      phases_completed: logs.distinct.pluck(:phase),
      latest_progress: logs.last&.progress_percentage || 0,
      average_rps: logs.with_performance_data.average(:records_per_second)&.round(2),
      peak_memory: logs.maximum("metrics->>'memory_usage'")&.to_f,
      peak_cpu: logs.maximum("metrics->>'cpu_usage'")&.to_f
    }
  end

  private

  # ============================================
  # プライベートメソッド
  # ============================================

  def set_defaults
    self.metrics ||= {}
    self.broadcasted ||= false
  end

  def update_parent_progress
    # 親のMigrationExecutionの進行状況を更新
    migration_execution.update_columns(
      processed_records: processed_records || migration_execution.processed_records,
      progress_percentage: progress_percentage,
      updated_at: Time.current
    ) if migration_execution
  end

  def should_broadcast?
    # リアルタイム配信が必要な条件
    log_level_info? || log_level_warn? || log_level_error? || log_level_fatal? ||
    (progress_percentage % 5 == 0) || # 5%刻みで配信
    requires_alert?
  end

  def schedule_broadcast
    # TODO: ActionCable統合時に実装
    # MigrationProgressBroadcastJob.perform_async(id)
    Rails.logger.debug "Scheduling broadcast for progress log #{id}"
  end

  def validate_metrics_structure
    return unless metrics.present?

    # メトリクスの基本的な構造チェック
    expected_numeric_keys = %w[cpu_usage memory_usage db_connections query_time records_per_second]

    expected_numeric_keys.each do |key|
      next unless metrics[key]

      unless metrics[key].is_a?(Numeric)
        errors.add(:metrics, "#{key}は数値である必要があります")
      end
    end
  end
end

# ============================================
# 設計ノート（継続的改善）
# ============================================

# 1. パフォーマンス最適化
#    - バルクインサート対応検討
#    - インデックス効果の継続測定
#    - JSON クエリの最適化

# 2. 運用性向上
#    - ログローテーション機能
#    - 自動アーカイブ（古いログ削除）
#    - メトリクス集約機能

# 3. ActionCable統合
#    - リアルタイム配信制御
#    - 配信頻度の最適化
#    - クライアント接続管理

# TODO: 拡張実装予定
# - [HIGH] ActionCable統合完了
# - [MEDIUM] アラート条件の詳細化
# - [MEDIUM] メトリクス可視化対応
# - [LOW] 機械学習による異常検知
