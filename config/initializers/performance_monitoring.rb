# frozen_string_literal: true

# パフォーマンス監視システム設定
# ============================================
# N+1クエリ再発防止・パフォーマンス継続監視
# Counter Cache最適化効果の継続確保
# ============================================

# 開発環境でのパフォーマンス監視設定
if Rails.env.development?
  # ============================================
  # Bullet gem設定強化（N+1クエリ検出）
  # ============================================
  Rails.application.configure do
    # Bullet有効化
    config.after_initialize do
      Bullet.enable = true

      # 検出対象設定
      Bullet.n_plus_one_query_enable = true
      Bullet.unused_eager_loading_enable = true
      Bullet.counter_cache_enable = true

      # 通知方法設定
      Bullet.console = true
      Bullet.rails_logger = true
      Bullet.add_footer = true

      # ブラウザ通知（JavaScript）
      Bullet.alert = true

      # より詳細なロギング
      Bullet.stacktrace_includes = [
        "app/controllers",
        "app/models",
        "app/views",
        "app/helpers"
      ]

      # 特定のクラス・メソッドの無視（必要に応じて）
      # Bullet.whitelist :type => :n_plus_one_query, :class_name => "User", :association => :comments
    end
  end
end

# ============================================
# パフォーマンス監視モジュール
# ============================================
module PerformanceMonitoring
  extend ActiveSupport::Concern

  # メモリ使用量監視
  class MemoryMonitor
    MEMORY_THRESHOLD_MB = 500 # メモリ使用量閾値（MB）

    def self.current_memory_usage
      # プロセスのメモリ使用量を取得（MB単位）
      begin
        if File.exist?("/proc/meminfo") && File.exist?("/proc/#{Process.pid}/status")
          # Linux環境（Docker含む）でのメモリ使用量取得
          status = File.read("/proc/#{Process.pid}/status")
          if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
            return match[1].to_i / 1024.0 # MB単位に変換
          end
        end

        # macOS等でpsコマンドが利用可能な場合
        output = `ps -o pid,rss -p #{Process.pid} 2>/dev/null`.split("\n")[1]
        return output.split[1].to_i / 1024.0 if output

        # フォールバック：Ruby標準のメモリ取得
        GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE] / 1024.0 / 1024.0
      rescue => e
        # エラー時はデフォルト値を返す
        Rails.logger.warn "Memory usage detection failed: #{e.message}" if defined?(Rails)
        100.0 # デフォルト値（MB）
      end
    end

    def self.check_memory_usage
      current_usage = current_memory_usage

      if current_usage > MEMORY_THRESHOLD_MB
        Rails.logger.warn "⚠️ Memory usage high: #{current_usage.round(2)}MB (threshold: #{MEMORY_THRESHOLD_MB}MB)"

        # 開発環境では詳細情報もログ出力
        if Rails.env.development?
          Rails.logger.warn "Current process: #{Process.pid}"
          Rails.logger.warn "Memory details: #{`ps aux | grep #{Process.pid} | grep -v grep`}"
        end

        return false
      end

      true
    end

    def self.log_memory_stats
      current_usage = current_memory_usage
      Rails.logger.info "📊 Memory usage: #{current_usage.round(2)}MB"
      current_usage
    end
  end

  # SQLクエリ数監視
  class QueryMonitor
    QUERY_COUNT_THRESHOLD = 10 # クエリ数閾値

    def self.monitor_request(&block)
      query_count = 0
      start_time = Time.current

      # ActiveRecordのクエリイベントを監視
      subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
        query_count += 1 unless args.last[:name] == "CACHE"
      end

      result = yield

      ActiveSupport::Notifications.unsubscribe(subscription)

      end_time = Time.current
      duration = (end_time - start_time) * 1000 # milliseconds

      # 閾値チェック
      if query_count > QUERY_COUNT_THRESHOLD
        Rails.logger.warn "⚠️ High query count detected: #{query_count} queries (threshold: #{QUERY_COUNT_THRESHOLD})"
        Rails.logger.warn "   Duration: #{duration.round(2)}ms"

        # スタックトレース（開発環境のみ）
        if Rails.env.development?
          Rails.logger.warn "   Caller: #{caller[0..2].join("\n   ")}"
        end
      end

      # 統計ログ
      Rails.logger.info "📊 SQL: #{query_count} queries, #{duration.round(2)}ms"

      {
        result: result,
        query_count: query_count,
        duration: duration
      }
    end
  end

  # レスポンス時間ベンチマーク
  class ResponseTimeBenchmark
    RESPONSE_TIME_THRESHOLDS = {
      "GET /store" => 50,                    # Store選択ページ（最適化済み）
      "GET /admin" => 200,                   # 管理者ダッシュボード
      "GET /admin/stores" => 300,            # 店舗一覧
      "GET /admin/inventories" => 400,       # 在庫一覧
      "POST /admin/inventories" => 1000,     # 在庫作成
      "PUT /admin/inventories/:id" => 800    # 在庫更新
    }.freeze

    def self.benchmark_endpoint(method, path, &block)
      start_time = Time.current

      result = yield

      end_time = Time.current
      duration = (end_time - start_time) * 1000 # milliseconds

      # エンドポイント識別子
      endpoint_key = "#{method.upcase} #{normalize_path(path)}"
      threshold = RESPONSE_TIME_THRESHOLDS[endpoint_key] || 500

      # 閾値チェック
      if duration > threshold
        Rails.logger.warn "⚠️ Slow response detected:"
        Rails.logger.warn "   Endpoint: #{endpoint_key}"
        Rails.logger.warn "   Duration: #{duration.round(2)}ms (threshold: #{threshold}ms)"
        Rails.logger.warn "   Slowdown: #{((duration / threshold - 1) * 100).round(1)}%"
      end

      # パフォーマンスログ
      Rails.logger.info "🚀 #{endpoint_key}: #{duration.round(2)}ms"

      {
        result: result,
        duration: duration,
        threshold: threshold,
        within_threshold: duration <= threshold
      }
    end

    private

    def self.normalize_path(path)
      # パラメータを正規化（/admin/inventories/123 → /admin/inventories/:id）
      normalized = path.gsub(/\/\d+(?=\/|$)/, "/:id")
      normalized
    end
  end

  # パフォーマンス統計収集
  class PerformanceStats
    def self.collect_system_stats
      {
        timestamp: Time.current.iso8601,
        memory_usage_mb: MemoryMonitor.current_memory_usage.round(2),
        active_record_pool_size: ActiveRecord::Base.connection_pool.size,
        active_record_pool_connections: ActiveRecord::Base.connection_pool.connections.size,
        redis_connected: redis_connected?,
        sidekiq_queue_size: sidekiq_queue_size,
        counter_cache_health: counter_cache_health_check
      }
    end

    def self.log_system_stats
      stats = collect_system_stats
      Rails.logger.info "📈 System Stats: #{stats.to_json}"
      stats
    end

    private

    def self.redis_connected?
      Redis.new.ping == "PONG"
    rescue
      false
    end

    def self.sidekiq_queue_size
      Sidekiq::Queue.new.size
    rescue
      0
    end

    def self.counter_cache_health_check
      # Store Counter Cacheの健全性チェック（サンプル）
      sample_store = Store.first
      return "no_stores" unless sample_store

      inconsistencies = sample_store.check_counter_cache_integrity
      inconsistencies.empty? ? "healthy" : "inconsistencies_detected"
    rescue
      "check_failed"
    end
  end
end

# ============================================
# Rack Middleware: パフォーマンス監視
# ============================================
class PerformanceMonitoringMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless Rails.env.development?

    request = Rack::Request.new(env)

    # 静的ファイルは監視対象外
    return @app.call(env) if static_file_request?(request)

    # パフォーマンス監視実行
    monitoring_result = PerformanceMonitoring::QueryMonitor.monitor_request do
      PerformanceMonitoring::ResponseTimeBenchmark.benchmark_endpoint(
        request.request_method,
        request.path
      ) do
        @app.call(env)
      end
    end

    # メモリ使用量チェック
    PerformanceMonitoring::MemoryMonitor.check_memory_usage

    # 統計情報の定期記録（10リクエストに1回）
    if rand(10) == 0
      PerformanceMonitoring::PerformanceStats.log_system_stats
    end

    monitoring_result[:result][:result]
  end

  private

  def static_file_request?(request)
    request.path.match?(/\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$/i)
  end
end

# ============================================
# 開発環境でのMiddleware追加
# ============================================
if Rails.env.development?
  Rails.application.configure do
    config.middleware.use PerformanceMonitoringMiddleware
  end
end

# ============================================
# TODO: 🔴 Phase 4（緊急）- パフォーマンス監視機能強化
# 優先度: 高（Phase 3完了後の継続監視）
# CLAUDE.md準拠: 実装済み最適化の継続監視
# ============================================
# 実装内容:
#   ✅ 完了: AdminInventoriesController最適化 (set_inventory条件分岐)
#   ✅ 完了: AdminStoresController最適化 (Counter Cache活用)
#   
#   🔄 進行中: より詳細なパフォーマンス監視
#   - アクション別最適化効果の定量測定
#   - includes使用状況の自動監視
#   - Counter Cache効果の継続確認
#   - レスポンス時間改善率の追跡
#
#   🔜 今後: 高度な分析機能
#   - N+1検出パターンのより具体的な分類
#   - メモリ使用量とクエリ数の相関分析
#   - 時系列でのパフォーマンス変化追跡
#   - 異常検知機能（統計的手法）
#
# 期待効果: 
#   - Phase 3最適化効果の継続確保
#   - パフォーマンス回帰の早期発見
#   - 新規実装時のパフォーマンス影響評価
# ============================================

# TODO: 🟡 Phase 5（推奨）- 本番環境対応
# 優先度: 中（本番運用時）
# 実装内容:
#   - APMツール連携（New Relic / DataDog）
#   - Grafana / Prometheus メトリクス送信
#   - Slack / メール通知機能
#   - パフォーマンス劣化時の自動スケーリング
# 期待効果: 本番環境での継続的パフォーマンス監視
# ============================================

# TODO: 🟢 Phase 6（長期）- 機械学習ベース予測
# 優先度: 低（システム安定化後）
# 実装内容:
#   - トラフィックパターン予測
#   - パフォーマンス劣化の予兆検知
#   - 自動最適化提案機能
#   - キャパシティプランニング支援
# 期待効果: 予防的パフォーマンス管理
# ============================================
