# frozen_string_literal: true

# ============================================
# Metrics Collector System
# ============================================
# アプリケーションメトリクス収集・集計システム
# CLAUDE.md準拠: 監視・可観測性の実装

class MetricsCollector
  include Singleton

  # ============================================
  # メトリクスタイプ定義
  # ============================================
  METRIC_TYPES = {
    # カウンター: 単調増加する値
    counter: :increment,
    # ゲージ: 上下する値（現在値）
    gauge: :set,
    # ヒストグラム: 分布を記録
    histogram: :observe,
    # サマリー: 統計情報を記録
    summary: :observe
  }.freeze

  # デフォルトの集計間隔
  AGGREGATION_INTERVALS = {
    realtime: 1,      # 1秒
    short: 60,        # 1分
    medium: 300,      # 5分
    long: 3600        # 1時間
  }.freeze

  # ============================================
  # 初期化
  # ============================================
  def initialize
    @metrics = {}
    @aggregated_metrics = {}
    @mutex = Mutex.new
    setup_default_metrics
  end

  # ============================================
  # メトリクス記録
  # ============================================

  # カウンターの増加
  def increment(metric_name, value = 1, labels = {})
    record_metric(:counter, metric_name, value, labels)
  end

  # ゲージの設定
  def gauge(metric_name, value, labels = {})
    record_metric(:gauge, metric_name, value, labels)
  end

  # ヒストグラムの記録
  def histogram(metric_name, value, labels = {})
    record_metric(:histogram, metric_name, value, labels)
  end

  # 処理時間の計測
  def measure_duration(metric_name, labels = {})
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    histogram("#{metric_name}_duration_seconds", duration, labels)
    result
  end

  # ============================================
  # アプリケーションメトリクス
  # ============================================

  # HTTPリクエストメトリクス
  def record_http_request(method:, path:, status:, duration:)
    labels = {
      method: method.to_s.upcase,
      path: normalize_path(path),
      status: status.to_s
    }

    increment("http_requests_total", 1, labels)
    histogram("http_request_duration_seconds", duration, labels)
    gauge("http_active_requests", active_request_count)
  end

  # データベースクエリメトリクス
  def record_db_query(sql:, name:, duration:, cached: false)
    query_type = extract_query_type(sql)
    labels = {
      type: query_type,
      name: name || "unknown",
      cached: cached.to_s
    }

    increment("db_queries_total", 1, labels)
    histogram("db_query_duration_seconds", duration, labels)
  end

  # Sidekiqジョブメトリクス
  def record_job_execution(job_class:, queue:, status:, duration:, retries: 0)
    labels = {
      job_class: job_class,
      queue: queue,
      status: status.to_s,
      retried: retries > 0 ? "true" : "false"
    }

    increment("sidekiq_jobs_total", 1, labels)
    histogram("sidekiq_job_duration_seconds", duration, labels)
    gauge("sidekiq_queue_size", queue_size(queue), queue: queue)
  end

  # キャッシュメトリクス
  def record_cache_operation(operation:, hit:, duration:)
    labels = {
      operation: operation.to_s,
      hit: hit ? "hit" : "miss"
    }

    increment("cache_operations_total", 1, labels)
    histogram("cache_operation_duration_seconds", duration, labels)
  end

  # ============================================
  # ビジネスメトリクス
  # ============================================

  # 在庫メトリクス
  def record_inventory_metrics
    gauge("inventory_total_value", calculate_total_inventory_value)
    gauge("inventory_low_stock_count", Inventory.low_stock.count)
    gauge("inventory_out_of_stock_count", Inventory.out_of_stock.count)
    
    # カテゴリ別在庫
    inventory_by_category.each do |category, count|
      gauge("inventory_items_by_category", count, category: category)
    end
  end

  # 店舗メトリクス
  def record_store_metrics
    Store.find_each do |store|
      labels = { store_id: store.id, store_name: store.name }
      
      gauge("store_inventory_value", store.total_inventory_value, labels)
      gauge("store_low_stock_items", store.low_stock_items_count, labels)
      gauge("store_pending_transfers", store.pending_transfers_count, labels)
    end
  end

  # アラートメトリクス
  def record_alert_triggered(alert_type:, severity:, store_id: nil)
    labels = {
      type: alert_type,
      severity: severity,
      store_id: store_id || "global"
    }

    increment("alerts_triggered_total", 1, labels)
  end

  # ============================================
  # システムメトリクス
  # ============================================

  # メモリ使用量
  def record_memory_metrics
    memory_info = get_memory_info
    
    gauge("memory_usage_bytes", memory_info[:rss])
    gauge("memory_heap_allocated_bytes", memory_info[:heap_allocated])
    gauge("memory_heap_free_bytes", memory_info[:heap_free])
  end

  # スレッド情報
  def record_thread_metrics
    gauge("threads_count", Thread.list.count)
    gauge("threads_running", Thread.list.count(&:alive?))
  end

  # GC統計
  def record_gc_metrics
    GC.stat.each do |key, value|
      gauge("gc_#{key}", value) if value.is_a?(Numeric)
    end
  end

  # ============================================
  # メトリクス取得
  # ============================================

  # 現在のメトリクス値を取得
  def get_metric(metric_name, labels = {})
    @mutex.synchronize do
      key = metric_key(metric_name, labels)
      @metrics[key]
    end
  end

  # 集計されたメトリクスを取得
  def get_aggregated_metrics(interval = :short)
    @mutex.synchronize do
      @aggregated_metrics[interval] || {}
    end
  end

  # ダッシュボード用データ取得
  def dashboard_metrics
    {
      system: {
        uptime: Process.clock_gettime(Process::CLOCK_UPTIME),
        memory_usage: get_memory_info[:rss],
        thread_count: Thread.list.count,
        gc_count: GC.count
      },
      application: {
        active_requests: active_request_count,
        total_requests: get_metric("http_requests_total") || 0,
        error_rate: calculate_error_rate,
        avg_response_time: calculate_avg_response_time
      },
      business: {
        total_inventory_value: calculate_total_inventory_value,
        low_stock_items: Inventory.low_stock.count,
        pending_transfers: InterStoreTransfer.pending.count,
        active_alerts: calculate_active_alerts
      },
      sidekiq: {
        processed: Sidekiq::Stats.new.processed,
        failed: Sidekiq::Stats.new.failed,
        queues: Sidekiq::Stats.new.queues,
        retry_size: Sidekiq::Stats.new.retry_size
      }
    }
  rescue => e
    Rails.logger.error "Failed to collect dashboard metrics: #{e.message}"
    {}
  end

  # ============================================
  # 定期集計
  # ============================================

  # メトリクスの集計（定期実行用）
  def aggregate_metrics(interval = :short)
    interval_seconds = AGGREGATION_INTERVALS[interval]
    
    @mutex.synchronize do
      @aggregated_metrics[interval] ||= {}
      
      # ヒストグラムとサマリーの統計計算
      @metrics.each do |key, metric|
        next unless metric[:type] == :histogram
        
        values = metric[:values] || []
        next if values.empty?
        
        stats = calculate_statistics(values)
        @aggregated_metrics[interval][key] = {
          count: values.size,
          sum: stats[:sum],
          avg: stats[:avg],
          min: stats[:min],
          max: stats[:max],
          p50: stats[:p50],
          p95: stats[:p95],
          p99: stats[:p99]
        }
        
        # 古いデータをクリア
        metric[:values] = []
      end
    end
  end

  # ============================================
  # プライベートメソッド
  # ============================================

  private

  def setup_default_metrics
    # デフォルトのメトリクスを初期化
    gauge("app_info", 1, version: Rails.application.config.version || "unknown")
  end

  def record_metric(type, name, value, labels)
    @mutex.synchronize do
      key = metric_key(name, labels)
      
      @metrics[key] ||= {
        type: type,
        name: name,
        labels: labels,
        value: 0,
        values: [],
        updated_at: Time.current
      }
      
      case type
      when :counter
        @metrics[key][:value] += value
      when :gauge
        @metrics[key][:value] = value
      when :histogram, :summary
        @metrics[key][:values] << value
      end
      
      @metrics[key][:updated_at] = Time.current
    end
  end

  def metric_key(name, labels)
    label_str = labels.sort.map { |k, v| "#{k}=#{v}" }.join(",")
    "#{name}{#{label_str}}"
  end

  def normalize_path(path)
    # パスを正規化（IDなどを置換）
    path.gsub(/\/\d+/, '/:id')
        .gsub(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, ':uuid')
  end

  def extract_query_type(sql)
    case sql.to_s.strip.upcase
    when /^SELECT/ then "select"
    when /^INSERT/ then "insert"
    when /^UPDATE/ then "update"
    when /^DELETE/ then "delete"
    else "other"
    end
  end

  def active_request_count
    # 実装依存: Rack middlewareで管理する必要あり
    Thread.current[:active_requests] || 0
  end

  def queue_size(queue_name)
    Sidekiq::Queue.new(queue_name).size
  rescue
    0
  end

  def calculate_total_inventory_value
    Rails.cache.fetch("metrics:inventory_total_value", expires_in: 5.minutes) do
      Inventory.sum("quantity * price")
    end
  end

  def inventory_by_category
    # カテゴリ別在庫数（カテゴリカラムが追加されるまでは暫定実装）
    Rails.cache.fetch("metrics:inventory_by_category", expires_in: 5.minutes) do
      categories = Hash.new(0)
      
      Inventory.find_each do |item|
        category = ApplicationHelper.categorize_by_name(item.name)
        categories[category] += item.quantity
      end
      
      categories
    end
  end

  def get_memory_info
    # プロセスのメモリ情報を取得
    if defined?(GetProcessMem)
      mem = GetProcessMem.new
      {
        rss: mem.bytes,
        heap_allocated: GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE],
        heap_free: GC.stat[:heap_free_slots] * GC::INTERNAL_CONSTANTS[:RVALUE_SIZE]
      }
    else
      # フォールバック: GC統計のみ
      {
        rss: 0,
        heap_allocated: GC.stat[:heap_allocated_pages] * 16384, # 概算値
        heap_free: GC.stat[:heap_free_slots] * 40 # 概算値
      }
    end
  end

  def calculate_error_rate
    total = get_metric("http_requests_total") || 0
    return 0.0 if total == 0
    
    errors = get_metric("http_requests_total", status: "500") || 0
    (errors.to_f / total * 100).round(2)
  end

  def calculate_avg_response_time
    # 最近の集計データから平均レスポンスタイムを計算
    recent_stats = @aggregated_metrics[:short]
    return 0 unless recent_stats
    
    response_times = recent_stats.select { |k, _| k.include?("http_request_duration_seconds") }
    return 0 if response_times.empty?
    
    total_sum = response_times.values.sum { |v| v[:sum] || 0 }
    total_count = response_times.values.sum { |v| v[:count] || 0 }
    
    return 0 if total_count == 0
    (total_sum / total_count * 1000).round(2) # ミリ秒に変換
  end

  def calculate_active_alerts
    # アクティブなアラート数を計算
    # TODO: AlertモデルやRedisベースの実装に置き換え
    0
  end

  def calculate_statistics(values)
    sorted = values.sort
    count = sorted.size
    
    {
      sum: sorted.sum,
      avg: sorted.sum.to_f / count,
      min: sorted.first,
      max: sorted.last,
      p50: percentile(sorted, 0.5),
      p95: percentile(sorted, 0.95),
      p99: percentile(sorted, 0.99)
    }
  end

  def percentile(sorted_array, percentile)
    return nil if sorted_array.empty?
    
    k = (percentile * (sorted_array.length - 1)).to_i
    f = (percentile * (sorted_array.length - 1)) % 1
    
    return sorted_array[k] if f == 0
    sorted_array[k] + (sorted_array[k + 1] - sorted_array[k]) * f
  end
end

# ============================================
# グローバルアクセス用のヘルパーメソッド
# ============================================
module Metrics
  module_function

  def collector
    MetricsCollector.instance
  end

  def increment(name, value = 1, labels = {})
    collector.increment(name, value, labels)
  end

  def gauge(name, value, labels = {})
    collector.gauge(name, value, labels)
  end

  def histogram(name, value, labels = {})
    collector.histogram(name, value, labels)
  end

  def measure_duration(name, labels = {}, &block)
    collector.measure_duration(name, labels, &block)
  end
end