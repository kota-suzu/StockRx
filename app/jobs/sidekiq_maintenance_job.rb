# frozen_string_literal: true

# ============================================
# Sidekiq Maintenance Job
# ============================================
# Sidekiq統計とキューの日次メンテナンス処理
# 定期実行：毎日深夜3時（sidekiq-scheduler経由）

class SidekiqMaintenanceJob < ApplicationJob
  # ============================================
  # Sidekiq Configuration
  # ============================================
  queue_as :default

  # Sidekiq specific options
  sidekiq_options retry: 1, backtrace: true, queue: :default

  # @param cleanup_old_jobs [Boolean] 古いジョブを削除するか（デフォルト：true）
  # @param notify_admins [Boolean] 管理者に結果を通知するか（デフォルト：false）
  def perform(cleanup_old_jobs = true, notify_admins = false)
    Rails.logger.info "Starting Sidekiq daily maintenance"

    maintenance_results = {}

    begin
      # 1. 統計情報収集
      maintenance_results[:stats] = collect_sidekiq_stats

      # 2. 古いジョブのクリーンアップ
      if cleanup_old_jobs
        maintenance_results[:cleanup] = perform_cleanup
      end

      # 3. キューレイテンシ分析
      maintenance_results[:latency_analysis] = analyze_queue_latency

      # 4. パフォーマンス監視
      maintenance_results[:performance] = monitor_performance

      # 5. 推奨アクション生成
      maintenance_results[:recommendations] = generate_recommendations(maintenance_results)

      # 結果をログに記録
      Rails.logger.info({
        event: "sidekiq_maintenance_completed",
        results: maintenance_results
      }.to_json)

      # 管理者通知（必要な場合）
      if notify_admins
        notify_maintenance_results(maintenance_results)
      end

      maintenance_results

    rescue => e
      Rails.logger.error({
        event: "sidekiq_maintenance_failed",
        error_class: e.class.name,
        error_message: e.message
      }.to_json)
      raise e
    end
  end

  private

  def collect_sidekiq_stats
    stats = Sidekiq::Stats.new

    {
      processed: stats.processed,
      failed: stats.failed,
      enqueued: stats.enqueued,
      scheduled: stats.scheduled_size,
      retry_size: stats.retry_size,
      dead_size: stats.dead_size,
      success_rate: calculate_success_rate(stats),
      workers_count: Sidekiq::Workers.new.size,
      processes_count: Sidekiq::ProcessSet.new.size
    }
  end

  def perform_cleanup
    cleanup_results = {}

    # 古いDead jobsの削除（90日以上前）
    dead_set = Sidekiq::DeadSet.new
    old_dead_jobs = dead_set.select { |job| job.created_at < 90.days.ago }
    old_dead_jobs.each(&:delete)
    cleanup_results[:dead_jobs_cleaned] = old_dead_jobs.size

    # 古いRetry jobsの削除（30日以上前で失敗が続いているもの）
    retry_set = Sidekiq::RetrySet.new
    old_retry_jobs = retry_set.select { |job| job.created_at < 30.days.ago && job.retry_count > 10 }
    old_retry_jobs.each(&:delete)
    cleanup_results[:retry_jobs_cleaned] = old_retry_jobs.size

    # Redis統計データのクリーンアップ
    cleanup_results[:redis_cleanup] = cleanup_redis_statistics

    Rails.logger.info "Cleanup completed: #{cleanup_results}"
    cleanup_results
  end

  def analyze_queue_latency
    latency_analysis = {}

    Sidekiq::Queue.all.each do |queue|
      latency = queue.latency
      status = case latency
      when 0..5 then "good"
      when 5..30 then "warning"
      else "critical"
      end

      latency_analysis[queue.name] = {
        latency: latency.round(2),
        status: status,
        size: queue.size
      }
    end

    latency_analysis
  end

  def monitor_performance
    performance_data = {}

    # メモリ使用量
    begin
      memory_usage = `ps -o rss= -p #{Process.pid}`.strip.to_i / 1024.0
      performance_data[:memory_mb] = memory_usage.round(2)
    rescue
      performance_data[:memory_mb] = nil
    end

    # CPU使用率（簡易版）
    begin
      cpu_usage = `ps -o %cpu= -p #{Process.pid}`.strip.to_f
      performance_data[:cpu_percent] = cpu_usage
    rescue
      performance_data[:cpu_percent] = nil
    end

    # Redis接続確認
    begin
      redis_ping_time = Benchmark.realtime do
        Sidekiq.redis { |conn| conn.ping }
      end
      performance_data[:redis_ping_ms] = (redis_ping_time * 1000).round(2)
    rescue => e
      performance_data[:redis_error] = e.message
    end

    performance_data
  end

  def generate_recommendations(results)
    recommendations = []

    # キューレイテンシに基づく推奨
    if results[:latency_analysis]&.any? { |_, data| data[:status] == "critical" }
      recommendations << "⚠️ Critical queue latency detected. Consider scaling workers."
    end

    # 失敗率に基づく推奨
    stats = results[:stats]
    if stats && stats[:success_rate] < 95.0
      recommendations << "⚠️ Low success rate (#{stats[:success_rate]}%). Review error logs."
    end

    # メモリ使用量に基づく推奨
    memory = results.dig(:performance, :memory_mb)
    if memory && memory > 500
      recommendations << "⚠️ High memory usage (#{memory}MB). Consider memory optimization."
    end

    # Dead jobsに基づく推奨
    dead_size = stats&.dig(:dead_size)
    if dead_size && dead_size > 100
      recommendations << "⚠️ High number of dead jobs (#{dead_size}). Review job reliability."
    end

    # 全て正常な場合
    if recommendations.empty?
      recommendations << "✅ Sidekiq system performance is healthy."
    end

    recommendations
  end

  def notify_maintenance_results(results)
    # 全管理者に通知
    Admin.find_each do |admin|
      begin
        ActionCable.server.broadcast("admin_#{admin.id}", {
          type: "sidekiq_maintenance_report",
          message: "Sidekiq日次メンテナンス完了",
          stats: results[:stats],
          cleanup: results[:cleanup],
          recommendations: results[:recommendations],
          timestamp: Time.current.iso8601
        })
      rescue => e
        Rails.logger.warn "Failed to notify admin #{admin.id} about maintenance: #{e.message}"
      end
    end
  end

  def calculate_success_rate(stats)
    total = stats.processed
    return 100.0 if total == 0

    success = total - stats.failed
    (success.to_f / total * 100).round(2)
  end

  def cleanup_redis_statistics
    cleaned_keys = 0

    if defined?(Sidekiq)
      Sidekiq.redis_pool.with do |redis|
        # 古いhistoryデータの削除（60日以上前）
        cutoff_timestamp = 60.days.ago.to_i

        %w[processed failed].each do |stat_type|
          key = "sidekiq:stat:#{stat_type}"
          removed = redis.zremrangebyscore(key, 0, cutoff_timestamp)
          cleaned_keys += removed
        end
      end
    end

    cleaned_keys
  end

  # TODO: 将来的な機能拡張
  # ============================================
  # 1. 高度な監視機能
  #    - Prometheus/Grafanaメトリクス連携
  #    - 異常検知アルゴリズム
  #    - 予測分析（リソース使用量予測）
  #
  # 2. 自動最適化機能
  #    - ワーカー数の動的調整
  #    - キュー優先度の自動調整
  #    - リソース使用量に基づく最適化
  #
  # 3. レポート機能強化
  #    - 週次・月次レポート生成
  #    - トレンド分析
  #    - パフォーマンス比較
  #
  # 4. アラート機能
  #    - Slack/Teams連携
  #    - SMS緊急通知
  #    - エスカレーション機能
  #
  # 5. バックアップ・復旧機能
  #    - ジョブキューのバックアップ
  #    - 設定の自動バックアップ
  #    - 障害時の自動復旧
end
