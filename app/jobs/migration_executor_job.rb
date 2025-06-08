# frozen_string_literal: true

# マイグレーション実行バックグラウンドジョブ
#
# CLAUDE.md準拠の設計:
# - エラーハンドリング（早期失敗、回復戦略）
# - 可観測性確保（構造化ログ、メトリクス）
# - 負荷制御（CPU・メモリ監視）
# - 分散ロック機能
class MigrationExecutorJob < ApplicationJob
  include ProgressNotifier

  # Sidekiq設定
  queue_as :critical

  # リトライ設定（指数バックオフ）
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # 致命的エラーでは即座に停止
  discard_on ActiveRecord::ActiveRecordError do |job, error|
    Rails.logger.fatal "Critical database error in migration execution: #{error.message}"
    job.arguments.first.mark_failed!(
      message: error.message,
      backtrace: error.backtrace&.first(20)
    )
  end

  # ============================================
  # メイン実行メソッド
  # ============================================

  def perform(migration_execution_id, options = {})
    @migration_execution = MigrationExecution.find(migration_execution_id)
    @options = options.with_indifferent_access
    @start_time = Time.current
    @abort_requested = false

    Rails.logger.info "Starting migration execution job for #{@migration_execution.version}"

    # 前提条件チェック
    validate_execution_preconditions

    # 分散ロック取得
    MigrationLock.with_lock(@migration_execution.version, timeout: 30.minutes) do
      execute_migration_with_monitoring
    end

  rescue MigrationLock::LockTimeoutError => e
    handle_lock_timeout_error(e)
  rescue => e
    handle_unexpected_error(e)
  ensure
    cleanup_execution
  end

  private

  # ============================================
  # 実行フロー制御
  # ============================================

  def execute_migration_with_monitoring
    # 実行開始
    start_execution

    # システムリソース監視開始
    monitoring_thread = start_system_monitoring

    begin
      # フェーズ別実行
      execute_initialization_phase
      execute_schema_change_phase if should_continue?
      execute_data_migration_phase if should_continue?
      execute_index_creation_phase if should_continue?
      execute_validation_phase if should_continue?
      execute_cleanup_phase if should_continue?

      # 成功完了
      complete_execution

    ensure
      # 監視スレッド停止
      monitoring_thread&.kill
    end
  end

  def should_continue?
    @migration_execution.reload
    !@abort_requested && @migration_execution.status_running?
  end

  # ============================================
  # フェーズ別実行
  # ============================================

  def execute_initialization_phase
    log_phase_start("initialization", "マイグレーション実行の初期化を開始")

    # 設定値の検証
    validate_configuration

    # システム状態チェック
    check_system_readiness

    # ロールバックデータの準備
    prepare_rollback_data

    log_phase_complete("initialization", "初期化が完了しました", progress: 10)
  end

  def execute_schema_change_phase
    log_phase_start("schema_change", "スキーマ変更を開始")

    # 実際のマイグレーション実行
    migration_instance = load_migration_class

    # アップメソッド実行（load_controlled実行）
    execute_with_load_control do
      migration_instance.migrate(:up)
    end

    log_phase_complete("schema_change", "スキーマ変更が完了しました", progress: 40)
  end

  def execute_data_migration_phase
    return unless requires_data_migration?

    log_phase_start("data_migration", "データ移行を開始")

    # バッチ処理でのデータ移行
    total_records = estimate_total_records
    @migration_execution.update!(total_records: total_records)

    process_data_in_batches(total_records)

    log_phase_complete("data_migration", "データ移行が完了しました", progress: 80)
  end

  def execute_index_creation_phase
    return unless requires_index_creation?

    log_phase_start("index_creation", "インデックス作成を開始")

    # 並列インデックス作成
    create_indexes_concurrently

    log_phase_complete("index_creation", "インデックス作成が完了しました", progress: 90)
  end

  def execute_validation_phase
    log_phase_start("validation", "検証を開始")

    # データ整合性検証
    validate_data_integrity

    # 制約チェック
    validate_constraints

    log_phase_complete("validation", "検証が完了しました", progress: 95)
  end

  def execute_cleanup_phase
    log_phase_start("cleanup", "クリーンアップを開始")

    # 一時データの削除
    cleanup_temporary_data

    # 統計情報更新
    update_database_statistics

    log_phase_complete("cleanup", "クリーンアップが完了しました", progress: 100)
  end

  # ============================================
  # データ処理
  # ============================================

  def process_data_in_batches(total_records)
    batch_size = @options[:batch_size] || 1000
    processed = 0
    current_batch = 1

    # バッチ処理ループ
    while processed < total_records && should_continue?
      batch_start_time = Time.current

      # 負荷制御チェック
      wait_for_system_resources if system_under_pressure?

      # バッチ処理実行
      batch_processed = process_single_batch(current_batch, batch_size)
      processed += batch_processed

      # 進行状況更新
      progress = (processed.to_f / total_records * 100).round(2)

      # 進行状況ログ作成
      create_progress_log(
        phase: "data_migration",
        progress: progress,
        message: "バッチ #{current_batch} 完了 (#{batch_processed} レコード)",
        processed_records: processed,
        batch_size: batch_processed,
        batch_number: current_batch,
        records_per_second: calculate_records_per_second(batch_processed, batch_start_time),
        estimated_remaining: estimate_remaining_time(processed, total_records)
      )

      current_batch += 1

      # 定期的な親レコード更新
      if current_batch % 10 == 0
        @migration_execution.update!(
          processed_records: processed,
          progress_percentage: progress
        )
      end
    end
  end

  def process_single_batch(batch_number, batch_size)
    # TODO: 実際のマイグレーションフレームワーク統合
    # migration_instance = load_migration_class
    # migration_instance.process_batch(batch_number, batch_size)

    # 現在はモックデータ
    sleep(0.1) # バッチ処理時間をシミュレート
    batch_size
  end

  # ============================================
  # システム監視・負荷制御
  # ============================================

  def start_system_monitoring
    Thread.new do
      loop do
        sleep(5) # 5秒間隔で監視

        begin
          metrics = collect_system_metrics

          # 危険レベルチェック
          if metrics[:cpu_usage] > 95 || metrics[:memory_usage] > 98
            Rails.logger.error "Critical system resource usage detected"
            @abort_requested = true
            break
          end

          # 警告レベルチェック
          if metrics[:cpu_usage] > 80 || metrics[:memory_usage] > 85
            Rails.logger.warn "High system resource usage: CPU=#{metrics[:cpu_usage]}%, Memory=#{metrics[:memory_usage]}%"
          end

        rescue => e
          Rails.logger.error "System monitoring error: #{e.message}"
        end
      end
    rescue => e
      Rails.logger.error "System monitoring thread error: #{e.message}"
    end
  end

  def system_under_pressure?
    metrics = collect_system_metrics

    metrics[:cpu_usage] > (@options[:cpu_threshold] || 75) ||
    metrics[:memory_usage] > (@options[:memory_threshold] || 80)
  end

  def wait_for_system_resources
    Rails.logger.info "System under pressure, waiting for resources..."

    start_wait = Time.current
    max_wait = 300 # 最大5分待機

    while system_under_pressure? && (Time.current - start_wait) < max_wait
      sleep(10)
      break unless should_continue?
    end

    if system_under_pressure?
      raise "System resources remain under pressure after waiting"
    end
  end

  def collect_system_metrics
    # TODO: 実際のシステムメトリクス収集実装
    # require 'sys/cpu'
    # require 'sys/proctable'

    # 現在はモックデータ
    {
      cpu_usage: rand(30..70),
      memory_usage: rand(40..75),
      db_connections: rand(5..15),
      query_time: rand(0.1..0.5),
      records_per_second: rand(800..1200)
    }
  end

  # ============================================
  # マイグレーション操作
  # ============================================

  def load_migration_class
    # TODO: 実際のマイグレーションクラス読み込み
    # migration_files = Dir[Rails.root.join("db/migrate/*#{@migration_execution.version}*.rb")]
    # migration_file = migration_files.first
    #
    # require migration_file
    # migration_class_name = File.basename(migration_file, ".rb").camelize
    # migration_class_name.constantize.new

    # 現在はモッククラス
    OpenStruct.new(
      migrate: ->(direction) {
        Rails.logger.info "Mock migration #{direction} for #{@migration_execution.version}"
        sleep(2) # マイグレーション実行時間をシミュレート
      }
    )
  end

  def execute_with_load_control
    execution_start = Time.current

    begin
      yield
    rescue => e
      execution_time = Time.current - execution_start
      Rails.logger.error "Migration execution failed after #{execution_time}s: #{e.message}"
      raise
    end

    execution_time = Time.current - execution_start
    Rails.logger.info "Migration executed successfully in #{execution_time}s"
  end

  # ============================================
  # ユーティリティ
  # ============================================

  def validate_execution_preconditions
    unless @migration_execution.can_execute?
      raise "Migration execution is not in valid state: #{@migration_execution.status}"
    end

    unless Current.admin = @migration_execution.admin
      raise "Cannot establish admin context for migration execution"
    end
  end

  def validate_configuration
    required_keys = %w[batch_size cpu_threshold memory_threshold]
    missing_keys = required_keys - (@migration_execution.configuration&.keys || [])

    if missing_keys.any?
      raise "Missing configuration keys: #{missing_keys.join(', ')}"
    end
  end

  def check_system_readiness
    # データベース接続チェック
    ActiveRecord::Base.connection.execute("SELECT 1")

    # 利用可能メモリチェック
    metrics = collect_system_metrics
    if metrics[:memory_usage] > 90
      raise "Insufficient memory available for migration execution"
    end
  end

  def prepare_rollback_data
    # TODO: ロールバック用データの収集
    rollback_data = {
      schema_snapshot: capture_schema_snapshot,
      critical_data: capture_critical_data,
      constraints: capture_constraints
    }

    @migration_execution.update!(rollback_data: rollback_data)
  end

  def capture_schema_snapshot
    # TODO: スキーマスナップショット取得
    {}
  end

  def capture_critical_data
    # TODO: 重要データの退避
    []
  end

  def capture_constraints
    # TODO: 制約情報の収集
    []
  end

  def requires_data_migration?
    # TODO: データ移行が必要かの判定
    @options[:data_migration] != false
  end

  def requires_index_creation?
    # TODO: インデックス作成が必要かの判定
    @options[:index_creation] != false
  end

  def estimate_total_records
    # TODO: 処理対象レコード数の推定
    @options[:estimated_records] || 10000
  end

  def create_indexes_concurrently
    # TODO: 並列インデックス作成
    Rails.logger.info "Creating indexes concurrently"
    sleep(1) # インデックス作成時間をシミュレート
  end

  def validate_data_integrity
    # TODO: データ整合性検証
    Rails.logger.info "Validating data integrity"
  end

  def validate_constraints
    # TODO: 制約検証
    Rails.logger.info "Validating constraints"
  end

  def cleanup_temporary_data
    # TODO: 一時データクリーンアップ
    Rails.logger.info "Cleaning up temporary data"
  end

  def update_database_statistics
    # TODO: 統計情報更新
    ActiveRecord::Base.connection.execute("ANALYZE") if Rails.env.production?
  end

  def calculate_records_per_second(records, start_time)
    elapsed = Time.current - start_time
    return 0 if elapsed <= 0
    (records / elapsed).round(2)
  end

  def estimate_remaining_time(processed, total)
    return nil if processed <= 0 || total <= 0

    elapsed = Time.current - @start_time
    rate = processed.to_f / elapsed
    remaining_records = total - processed

    (remaining_records / rate).round(0)
  end

  # ============================================
  # 実行ライフサイクル管理
  # ============================================

  def start_execution
    @migration_execution.start_execution!
    Rails.logger.info "Migration execution started: #{@migration_execution.version}"
  end

  def complete_execution
    @migration_execution.mark_completed!

    execution_time = Time.current - @start_time
    Rails.logger.info "Migration execution completed successfully in #{execution_time}s"

    # 完了通知
    create_progress_log(
      phase: "cleanup",
      progress: 100,
      message: "マイグレーション実行が正常に完了しました",
      level: "info"
    )
  end

  def cleanup_execution
    Rails.logger.info "Cleaning up migration execution resources"
    # リソースクリーンアップ処理
  end

  # ============================================
  # エラーハンドリング
  # ============================================

  def handle_lock_timeout_error(error)
    Rails.logger.error "Failed to acquire migration lock: #{error.message}"

    @migration_execution.mark_failed!(
      message: "マイグレーションロックの取得に失敗しました: #{error.message}",
      backtrace: error.backtrace&.first(10)
    )
  end

  def handle_unexpected_error(error)
    Rails.logger.error "Unexpected migration execution error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n") if error.backtrace

    @migration_execution.mark_failed!(
      message: error.message,
      backtrace: error.backtrace&.first(20)
    )

    # エラー通知
    create_progress_log(
      phase: @migration_execution.latest_progress_log&.phase || "unknown",
      progress: @migration_execution.progress_percentage,
      message: "マイグレーション実行中にエラーが発生しました: #{error.message}",
      level: "error"
    )
  end

  # ============================================
  # ログ・進行状況管理
  # ============================================

  def log_phase_start(phase, message)
    Rails.logger.info "Phase started: #{phase} - #{message}"

    create_progress_log(
      phase: phase,
      progress: @migration_execution.progress_percentage,
      message: message,
      level: "info"
    )
  end

  def log_phase_complete(phase, message, progress:)
    Rails.logger.info "Phase completed: #{phase} - #{message}"

    create_progress_log(
      phase: phase,
      progress: progress,
      message: message,
      level: "info"
    )

    # 親レコードの進行状況更新
    @migration_execution.update!(progress_percentage: progress)
  end

  def create_progress_log(phase:, progress:, message:, level: "info", **options)
    metrics = collect_system_metrics

    MigrationProgressLog.create!(
      migration_execution: @migration_execution,
      phase: phase,
      progress_percentage: progress,
      message: message,
      log_level: level,
      processed_records: options[:processed_records],
      current_batch_size: options[:batch_size],
      current_batch_number: options[:batch_number],
      records_per_second: options[:records_per_second],
      estimated_remaining_seconds: options[:estimated_remaining],
      metrics: metrics
    )
  rescue => e
    Rails.logger.error "Failed to create progress log: #{e.message}"
  end
end

# ============================================
# 設計ノート（CLAUDE.md準拠）
# ============================================

# 1. エラーハンドリング戦略
#    - 早期失敗による問題の迅速な特定
#    - 回復可能エラーの適切なリトライ
#    - 致命的エラーでの安全な停止

# 2. 負荷制御機能
#    - リアルタイムシステム監視
#    - 動的負荷制御による安定性確保
#    - 緊急停止機能

# 3. 可観測性確保
#    - 詳細な進行状況ログ
#    - システムメトリクス収集
#    - パフォーマンス指標測定

# 4. 分散実行対応
#    - マイグレーションロック機能
#    - 複数サーバー環境での安全性

# TODO: 実装完了項目
# - [HIGH] 実際のマイグレーションクラス統合
# - [HIGH] システムメトリクス収集実装
# - [MEDIUM] ActionCable統合（リアルタイム通知）
# - [MEDIUM] ロールバック機能完全実装
# - [LOW] パフォーマンス最適化
