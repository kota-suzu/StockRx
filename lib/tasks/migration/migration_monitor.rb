# frozen_string_literal: true

# MigrationMonitor - マイグレーション監視システム
#
# マイグレーションの実行状況をリアルタイムで監視し、
# 異常を検知した場合はアラートを送信
class MigrationMonitor
  include ActionView::Helpers::DateHelper

  # 監視設定
  MONITORING_CONFIG = {
    check_interval: 30, # 秒
    slow_query_threshold: 60, # 秒
    error_rate_threshold: 0.05, # 5%
    memory_usage_alert: 85, # %
    cpu_usage_alert: 80, # %
    stalled_detection: 300 # 5分間進捗なし
  }.freeze

  class << self
    # ============================================
    # 監視開始・停止
    # ============================================

    def start_monitoring(migration_name, options = {})
      monitor_key = "migration_monitor:#{migration_name}"

      # 監視情報の初期化
      monitor_data = {
        migration_name: migration_name,
        start_time: Time.current,
        status: "running",
        progress: 0,
        total_records: options[:total_records] || 0,
        processed_records: 0,
        errors: [],
        metrics: [],
        alerts: [],
        options: options
      }

      # Redisに保存（本番環境）またはメモリに保存（開発環境）
      store_monitor_data(monitor_key, monitor_data)

      # 非同期監視タスクの開始
      start_async_monitoring(monitor_key) if options[:async] != false

      Rails.logger.info "Started monitoring migration: #{migration_name}"
      monitor_key
    end

    def stop_monitoring(monitor_key, status = "completed")
      monitor_data = fetch_monitor_data(monitor_key)
      return unless monitor_data

      monitor_data[:status] = status
      monitor_data[:end_time] = Time.current
      monitor_data[:duration] = monitor_data[:end_time] - monitor_data[:start_time]

      store_monitor_data(monitor_key, monitor_data)

      # 最終レポートの生成
      generate_final_report(monitor_data)

      Rails.logger.info "Stopped monitoring: #{monitor_data[:migration_name]}"
    end

    # ============================================
    # 進捗更新
    # ============================================

    def update_progress(monitor_key, processed_records, options = {})
      monitor_data = fetch_monitor_data(monitor_key)
      return unless monitor_data

      monitor_data[:processed_records] = processed_records
      monitor_data[:progress] = calculate_progress(processed_records, monitor_data[:total_records])
      monitor_data[:last_update] = Time.current

      # エラー情報の追加
      if options[:error]
        monitor_data[:errors] << {
          message: options[:error],
          timestamp: Time.current,
          record_id: options[:record_id]
        }
      end

      # メトリクスの記録
      if options[:metrics]
        monitor_data[:metrics] << options[:metrics].merge(timestamp: Time.current)
      end

      store_monitor_data(monitor_key, monitor_data)

      # 異常検知
      check_for_anomalies(monitor_data)
    end

    # ============================================
    # アラート機能
    # ============================================

    def send_alert(monitor_data, alert_type, message)
      alert = {
        type: alert_type,
        message: message,
        timestamp: Time.current,
        migration_name: monitor_data[:migration_name],
        severity: determine_severity(alert_type)
      }

      monitor_data[:alerts] << alert

      # アラート送信（実装に応じて選択）
      case alert[:severity]
      when "critical"
        send_critical_alert(alert)
      when "warning"
        send_warning_alert(alert)
      else
        Rails.logger.warn "Alert: #{alert.to_json}"
      end
    end

    # ============================================
    # 監視情報の取得
    # ============================================

    def get_status(monitor_key)
      monitor_data = fetch_monitor_data(monitor_key)
      return nil unless monitor_data

      {
        migration_name: monitor_data[:migration_name],
        status: monitor_data[:status],
        progress: monitor_data[:progress],
        processed: monitor_data[:processed_records],
        total: monitor_data[:total_records],
        error_count: monitor_data[:errors].size,
        error_rate: calculate_error_rate(monitor_data),
        elapsed_time: Time.current - monitor_data[:start_time],
        eta: calculate_eta(monitor_data),
        current_metrics: monitor_data[:metrics].last
      }
    end

    def get_all_active_migrations
      # Redisまたはメモリストアから全ての実行中のマイグレーションを取得
      pattern = "migration_monitor:*"
      keys = if defined?(Redis) && Redis.current
               Redis.current.keys(pattern)
      else
               @memory_store&.keys&.select { |k| k.match?(pattern) } || []
      end

      keys.map do |key|
        data = fetch_monitor_data(key)
        next unless data && data[:status] == "running"

        get_status(key)
      end.compact
    end

    private

    # ============================================
    # データストア操作
    # ============================================

    def store_monitor_data(key, data)
      if defined?(Redis) && Redis.current
        Redis.current.set(key, data.to_json, ex: 86400) # 24時間で自動削除
      else
        @memory_store ||= {}
        @memory_store[key] = data
      end
    end

    def fetch_monitor_data(key)
      data = if defined?(Redis) && Redis.current
               json = Redis.current.get(key)
               JSON.parse(json, symbolize_names: true) if json
      else
               @memory_store&.[](key)
      end

      data
    end

    # ============================================
    # 非同期監視
    # ============================================

    def start_async_monitoring(monitor_key)
      # バックグラウンドジョブまたはスレッドで監視
      Thread.new do
        loop do
          sleep MONITORING_CONFIG[:check_interval]

          monitor_data = fetch_monitor_data(monitor_key)
          break unless monitor_data && monitor_data[:status] == "running"

          # 定期チェック
          check_system_resources(monitor_data)
          check_for_stalled_migration(monitor_data)

          store_monitor_data(monitor_key, monitor_data)
        end
      rescue => e
        Rails.logger.error "Monitoring error: #{e.message}"
      end
    end

    # ============================================
    # 異常検知
    # ============================================

    def check_for_anomalies(monitor_data)
      # エラー率チェック
      error_rate = calculate_error_rate(monitor_data)
      if error_rate > MONITORING_CONFIG[:error_rate_threshold]
        send_alert(monitor_data, :high_error_rate,
                  "エラー率が閾値を超えました: #{(error_rate * 100).round(2)}%")
      end

      # 処理速度の低下検知
      if monitor_data[:metrics].size > 5
        recent_speeds = monitor_data[:metrics].last(5).map { |m| m[:records_per_second] || 0 }
        avg_speed = recent_speeds.sum / recent_speeds.size

        if avg_speed < 1 # 1レコード/秒未満
          send_alert(monitor_data, :slow_processing,
                    "処理速度が低下しています: #{avg_speed.round(2)} records/s")
        end
      end
    end

    def check_system_resources(monitor_data)
      cpu = get_cpu_usage
      memory = get_memory_usage

      if cpu > MONITORING_CONFIG[:cpu_usage_alert]
        send_alert(monitor_data, :high_cpu, "CPU使用率が高い: #{cpu}%")
      end

      if memory > MONITORING_CONFIG[:memory_usage_alert]
        send_alert(monitor_data, :high_memory, "メモリ使用率が高い: #{memory}%")
      end
    end

    def check_for_stalled_migration(monitor_data)
      return unless monitor_data[:last_update]

      stalled_duration = Time.current - monitor_data[:last_update]
      if stalled_duration > MONITORING_CONFIG[:stalled_detection]
        send_alert(monitor_data, :stalled,
                  "マイグレーションが停止している可能性があります (#{stalled_duration.round}秒間更新なし)")
      end
    end

    # ============================================
    # 計算ヘルパー
    # ============================================

    def calculate_progress(processed, total)
      return 0 if total.zero?
      [ (processed.to_f / total * 100).round(2), 100 ].min
    end

    def calculate_error_rate(monitor_data)
      total = monitor_data[:processed_records]
      return 0 if total.zero?

      monitor_data[:errors].size.to_f / total
    end

    def calculate_eta(monitor_data)
      return nil unless monitor_data[:processed_records] > 0

      elapsed = Time.current - monitor_data[:start_time]
      rate = monitor_data[:processed_records] / elapsed
      remaining = monitor_data[:total_records] - monitor_data[:processed_records]

      return nil if rate.zero? || remaining <= 0

      eta_seconds = remaining / rate
      monitor_data[:start_time] + elapsed + eta_seconds
    end

    def determine_severity(alert_type)
      case alert_type
      when :stalled, :high_error_rate
        "critical"
      when :high_cpu, :high_memory, :slow_processing
        "warning"
      else
        "info"
      end
    end

    # ============================================
    # アラート送信
    # ============================================

    def send_critical_alert(alert)
      # 実装例：Slack、メール、PagerDuty等への送信
      Rails.logger.error "CRITICAL ALERT: #{alert.to_json}"

      # Slackへの送信例（slack-notifier gem使用時）
      # notifier = Slack::Notifier.new(webhook_url)
      # notifier.post(
      #   text: "🚨 Critical Migration Alert",
      #   attachments: [{
      #     color: 'danger',
      #     fields: [
      #       { title: 'Migration', value: alert[:migration_name] },
      #       { title: 'Alert Type', value: alert[:type] },
      #       { title: 'Message', value: alert[:message] }
      #     ]
      #   }]
      # )
    end

    def send_warning_alert(alert)
      Rails.logger.warn "WARNING ALERT: #{alert.to_json}"
    end

    # ============================================
    # レポート生成
    # ============================================

    def generate_final_report(monitor_data)
      report = {
        migration_name: monitor_data[:migration_name],
        status: monitor_data[:status],
        duration: distance_of_time_in_words(monitor_data[:duration]),
        total_records: monitor_data[:total_records],
        processed_records: monitor_data[:processed_records],
        error_count: monitor_data[:errors].size,
        error_rate: "#{(calculate_error_rate(monitor_data) * 100).round(2)}%",
        alerts_count: monitor_data[:alerts].size,
        performance_summary: generate_performance_summary(monitor_data)
      }

      Rails.logger.info "Migration Report: #{report.to_json}"

      # レポートをファイルに保存
      save_report_to_file(report, monitor_data)

      report
    end

    def generate_performance_summary(monitor_data)
      return {} if monitor_data[:metrics].empty?

      metrics = monitor_data[:metrics]
      speeds = metrics.map { |m| m[:records_per_second] || 0 }.compact

      {
        average_speed: speeds.sum / speeds.size,
        max_speed: speeds.max,
        min_speed: speeds.min,
        total_batches: metrics.size
      }
    end

    def save_report_to_file(report, monitor_data)
      reports_dir = Rails.root.join("log", "migrations")
      FileUtils.mkdir_p(reports_dir)

      filename = "#{monitor_data[:migration_name]}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      filepath = reports_dir.join(filename)

      File.write(filepath, JSON.pretty_generate(report))
      Rails.logger.info "Report saved to: #{filepath}"
    end

    # ============================================
    # システムリソース取得
    # ============================================

    def get_cpu_usage
      `ps -o %cpu= -p #{Process.pid}`.to_f
    rescue
      0
    end

    def get_memory_usage
      rss = `ps -o rss= -p #{Process.pid}`.to_i
      total = `sysctl -n hw.memsize`.to_i / 1024 rescue 8_000_000
      (rss.to_f / total * 100).round(2)
    rescue
      0
    end
  end
end

# TODO: 今後の拡張予定
# 1. Prometheusメトリクス連携
# 2. Grafanaダッシュボード統合
# 3. 機械学習による異常検知
# 4. 複数マイグレーションの依存関係管理
# 5. ロールバック自動実行の判断ロジック
