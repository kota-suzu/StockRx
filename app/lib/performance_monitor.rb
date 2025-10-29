# frozen_string_literal: true

# Performance Monitor
# =====================================
# 責務: バックグラウンドジョブのパフォーマンス監視
# 目的: リアルタイムのパフォーマンスメトリクス収集
# =====================================
class PerformanceMonitor
  include ActiveModel::Model

  attr_reader :job_id, :start_time, :metrics

  def initialize(job_id)
    @job_id = job_id
    @start_time = nil
    @metrics = {
      processed_records: 0,
      batch_count: 0,
      total_processing_time: 0.0,
      average_batch_time: 0.0,
      peak_memory_usage: 0,
      errors: []
    }
  end

  # 監視開始
  def start_monitoring
    @start_time = Time.current
    @metrics[:started_at] = @start_time.iso8601

    log_monitoring_start
  end

  # 監視停止
  def stop_monitoring
    return unless @start_time

    @metrics[:stopped_at] = Time.current.iso8601
    @metrics[:total_duration] = calculate_total_duration

    log_monitoring_stop
  end

  # バッチ完了の記録
  def record_batch_completion(batch_size)
    @metrics[:processed_records] += batch_size
    @metrics[:batch_count] += 1

    # バッチごとの処理時間を記録
    batch_time = calculate_batch_time
    @metrics[:total_processing_time] += batch_time
    @metrics[:average_batch_time] = @metrics[:total_processing_time] / @metrics[:batch_count]

    # メモリ使用量の記録
    current_memory = get_current_memory_usage
    @metrics[:peak_memory_usage] = [ @metrics[:peak_memory_usage], current_memory ].max

    log_batch_completion(batch_size, batch_time, current_memory)
  end

  # エラーの記録
  def record_error(error)
    error_data = {
      error_class: error.class.name,
      error_message: error.message,
      timestamp: Time.current.iso8601,
      processed_records: @metrics[:processed_records]
    }

    @metrics[:errors] << error_data
    log_error_recorded(error_data)
  end

  # パフォーマンス統計の取得
  def performance_stats
    {
      job_id: @job_id,
      total_duration: calculate_total_duration,
      records_per_second: calculate_records_per_second,
      average_batch_time: @metrics[:average_batch_time].round(3),
      peak_memory_mb: (@metrics[:peak_memory_usage] / 1024.0 / 1024.0).round(2),
      error_count: @metrics[:errors].size,
      efficiency_score: calculate_efficiency_score
    }
  end

  # 処理効率の評価
  def calculate_efficiency_score
    return 0 if @metrics[:processed_records].zero?

    # 基準: 1秒間に100レコード処理、エラー率5%以下で満点
    records_per_second = calculate_records_per_second
    error_rate = @metrics[:errors].size.to_f / @metrics[:processed_records]

    # 処理速度スコア (最大50点)
    speed_score = [ records_per_second / 100.0 * 50, 50 ].min

    # エラー率スコア (最大50点)
    error_score = [ 50 - (error_rate * 1000), 0 ].max

    (speed_score + error_score).round(1)
  end

  private

  # 総処理時間の計算
  def calculate_total_duration
    return 0 unless @start_time
    Time.current - @start_time
  end

  # 1秒間あたりの処理レコード数
  def calculate_records_per_second
    duration = calculate_total_duration
    return 0 if duration.zero?

    (@metrics[:processed_records] / duration).round(2)
  end

  # バッチ処理時間の計算（簡易版）
  def calculate_batch_time
    # 実際のバッチ処理時間を測定するには、より詳細な実装が必要
    # ここでは平均的な処理時間を推定
    return 0.1 if @metrics[:batch_count].zero?

    @metrics[:total_processing_time] / @metrics[:batch_count]
  end

  # 現在のメモリ使用量取得
  def get_current_memory_usage
    return 0 unless defined?(ObjectSpace)

    ObjectSpace.count_objects[:TOTAL] rescue 0
  end

  # 監視開始ログ
  def log_monitoring_start
    Rails.logger.info({
      event: "performance_monitoring_started",
      job_id: @job_id,
      started_at: @start_time.iso8601
    }.to_json)
  end

  # 監視停止ログ
  def log_monitoring_stop
    Rails.logger.info({
      event: "performance_monitoring_stopped",
      job_id: @job_id,
      performance_stats: performance_stats
    }.to_json)
  end

  # バッチ完了ログ
  def log_batch_completion(batch_size, batch_time, memory_usage)
    Rails.logger.debug({
      event: "batch_completion_recorded",
      job_id: @job_id,
      batch_size: batch_size,
      batch_time: batch_time.round(3),
      memory_usage_mb: (memory_usage / 1024.0 / 1024.0).round(2),
      total_processed: @metrics[:processed_records]
    }.to_json)
  end

  # エラー記録ログ
  def log_error_recorded(error_data)
    Rails.logger.warn({
      event: "error_recorded_in_monitoring",
      job_id: @job_id,
      error_data: error_data
    }.to_json)
  end
end
