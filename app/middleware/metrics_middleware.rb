# frozen_string_literal: true

# ============================================
# Metrics Collection Middleware
# ============================================
# HTTPリクエストのメトリクスを自動収集するRackミドルウェア
# CLAUDE.md準拠: パフォーマンス監視の実装

class MetricsMiddleware
  # 除外するパス（ヘルスチェックなど）
  EXCLUDED_PATHS = %w[
    /health
    /metrics
    /favicon.ico
    /assets
    /cable
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    # 除外パスはスキップ
    return @app.call(env) if excluded_path?(env["PATH_INFO"])

    # アクティブリクエスト数を増加
    increment_active_requests

    # リクエスト開始時刻を記録
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    begin
      # アプリケーションを実行
      status, headers, response = @app.call(env)
      
      # メトリクスを記録
      record_request_metrics(env, status, start_time)
      
      [status, headers, response]
    rescue => e
      # エラーメトリクスを記録
      record_request_metrics(env, 500, start_time)
      raise e
    ensure
      # アクティブリクエスト数を減少
      decrement_active_requests
    end
  end

  private

  def excluded_path?(path)
    EXCLUDED_PATHS.any? { |excluded| path.start_with?(excluded) }
  end

  def increment_active_requests
    Thread.current[:active_requests] ||= 0
    Thread.current[:active_requests] += 1
  end

  def decrement_active_requests
    Thread.current[:active_requests] ||= 1
    Thread.current[:active_requests] -= 1
  end

  def record_request_metrics(env, status, start_time)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    
    MetricsCollector.instance.record_http_request(
      method: env["REQUEST_METHOD"],
      path: env["PATH_INFO"],
      status: status,
      duration: duration
    )
  rescue => e
    Rails.logger.warn "Failed to record request metrics: #{e.message}"
  end
end

# ============================================
# Database Query Instrumentation
# ============================================
# Active Recordのクエリメトリクスを収集

module DatabaseMetrics
  extend ActiveSupport::Concern

  included do
    # SQLクエリの実行を監視
    ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, start, finish, _id, payload|
      # SCHEMA関連のクエリは除外
      next if payload[:name] == "SCHEMA"
      next if payload[:sql]&.match?(/^(BEGIN|COMMIT|ROLLBACK|PRAGMA)/i)

      duration = finish - start
      
      MetricsCollector.instance.record_db_query(
        sql: payload[:sql],
        name: payload[:name],
        duration: duration,
        cached: payload[:cached] || false
      )
    rescue => e
      Rails.logger.warn "Failed to record database metrics: #{e.message}"
    end
  end
end

# ============================================
# Cache Instrumentation
# ============================================
# キャッシュ操作のメトリクスを収集

module CacheMetrics
  extend ActiveSupport::Concern

  included do
    # キャッシュ読み取りを監視
    ActiveSupport::Notifications.subscribe("cache_read.active_support") do |_name, start, finish, _id, payload|
      duration = finish - start
      hit = payload[:hit] || false
      
      MetricsCollector.instance.record_cache_operation(
        operation: :read,
        hit: hit,
        duration: duration
      )
    rescue => e
      Rails.logger.warn "Failed to record cache read metrics: #{e.message}"
    end

    # キャッシュ書き込みを監視
    ActiveSupport::Notifications.subscribe("cache_write.active_support") do |_name, start, finish, _id, _payload|
      duration = finish - start
      
      MetricsCollector.instance.record_cache_operation(
        operation: :write,
        hit: true,
        duration: duration
      )
    rescue => e
      Rails.logger.warn "Failed to record cache write metrics: #{e.message}"
    end
  end
end

# ============================================
# Sidekiq Metrics
# ============================================
# Sidekiqジョブのメトリクスを収集

module SidekiqMetrics
  class Middleware
    def call(worker, job, queue)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      
      begin
        yield
        
        # 成功時のメトリクス
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        record_job_metrics(worker, job, queue, :success, duration)
      rescue => e
        # 失敗時のメトリクス
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
        record_job_metrics(worker, job, queue, :failure, duration)
        raise e
      end
    end

    private

    def record_job_metrics(worker, job, queue, status, duration)
      MetricsCollector.instance.record_job_execution(
        job_class: worker.class.name,
        queue: queue,
        status: status,
        duration: duration,
        retries: job["retry_count"] || 0
      )
    rescue => e
      Rails.logger.warn "Failed to record Sidekiq metrics: #{e.message}"
    end
  end
end

# ============================================
# Periodic Metrics Collection
# ============================================
# 定期的なメトリクス収集ジョブ

class CollectMetricsJob < ApplicationJob
  queue_as :low

  def perform
    collector = MetricsCollector.instance
    
    # システムメトリクス
    collector.record_memory_metrics
    collector.record_thread_metrics
    collector.record_gc_metrics
    
    # ビジネスメトリクス
    collector.record_inventory_metrics
    collector.record_store_metrics
    
    # 集計処理
    collector.aggregate_metrics(:short)
    collector.aggregate_metrics(:medium) if Time.current.min % 5 == 0
    collector.aggregate_metrics(:long) if Time.current.min == 0
    
    Rails.logger.info "Metrics collection completed"
  rescue => e
    Rails.logger.error "Failed to collect metrics: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end