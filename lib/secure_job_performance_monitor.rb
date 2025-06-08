# frozen_string_literal: true

# ============================================
# Secure Job Performance Monitor
# ============================================
# 目的:
#   - ActiveJobのパフォーマンス監視とメモリ使用量追跡
#   - セキュリティ機能による影響の測定
#   - リアルタイムアラートとボトルネック検出
#
# 機能:
#   - CPU使用率、メモリ使用量の詳細監視
#   - 処理時間の統計分析とトレンド追跡
#   - アラート通知とパフォーマンス劣化検出
#
class SecureJobPerformanceMonitor
  # ============================================
  # 設定定数
  # ============================================

  # パフォーマンス監視設定
  PERFORMANCE_THRESHOLDS = {
    # 処理時間の警告しきい値
    slow_job_threshold: 5.0,           # 5秒以上で警告
    very_slow_job_threshold: 30.0,     # 30秒以上で緊急警告

    # メモリ使用量の警告しきい値
    memory_warning_threshold: 100.megabytes,    # 100MB以上で警告
    memory_critical_threshold: 500.megabytes,   # 500MB以上で緊急警告

    # サニタイズ処理の許容限界
    sanitization_time_limit: 1.0,      # サニタイズに1秒以上は異常
    sanitization_memory_limit: 50.megabytes, # サニタイズで50MB以上は異常

    # 統計データ保持期間
    stats_retention_hours: 24,         # 24時間分の統計を保持
    detailed_retention_hours: 1        # 1時間分の詳細データを保持
  }.freeze

  # Redis キープレフィックス
  REDIS_KEY_PREFIX = "secure_job_perf"

  # ============================================
  # クラスメソッド
  # ============================================

  class << self
    # パフォーマンス監視の開始
    #
    # @param job_class [String] ジョブクラス名
    # @param job_id [String] ジョブID
    # @param args_size [Integer] 引数のサイズ
    # @return [Hash] 監視開始時の基本情報
    def start_monitoring(job_class, job_id, args_size = 0)
      start_time = Time.current
      initial_memory = current_memory_usage

      monitoring_data = {
        job_class: job_class,
        job_id: job_id,
        args_size: args_size,
        start_time: start_time,
        initial_memory: initial_memory,
        process_id: Process.pid,
        thread_id: Thread.current.object_id
      }

      # Redis に開始情報を保存
      store_monitoring_start(monitoring_data)

      Rails.logger.debug({
        event: "performance_monitoring_started",
        **monitoring_data.except(:start_time).merge(start_time: start_time.iso8601)
      }.to_json) if debug_mode?

      monitoring_data
    end

    # パフォーマンス監視の終了
    #
    # @param monitoring_data [Hash] 監視開始時のデータ
    # @param success [Boolean] ジョブが成功したかどうか
    # @param error [Exception, nil] エラー情報（失敗時）
    # @return [Hash] 監視結果の詳細
    def end_monitoring(monitoring_data, success: true, error: nil)
      end_time = Time.current
      final_memory = current_memory_usage
      duration = end_time - monitoring_data[:start_time]
      memory_delta = final_memory - monitoring_data[:initial_memory]

      performance_result = {
        **monitoring_data,
        end_time: end_time,
        duration: duration,
        final_memory: final_memory,
        memory_delta: memory_delta,
        success: success,
        error_class: error&.class&.name,
        error_message: error&.message
      }

      # 統計データの更新
      update_performance_statistics(performance_result)

      # 警告チェック
      check_performance_warnings(performance_result)

      # Redis からの監視データ削除
      cleanup_monitoring_data(monitoring_data[:job_id])

      Rails.logger.info({
        event: "performance_monitoring_completed",
        **performance_result.except(:start_time, :end_time).merge(
          start_time: monitoring_data[:start_time].iso8601,
          end_time: end_time.iso8601,
          duration_ms: (duration * 1000).round(2)
        )
      }.to_json)

      performance_result
    end

    # サニタイズ処理のパフォーマンス監視
    #
    # @param job_class [String] ジョブクラス名
    # @param args_count [Integer] 引数の数
    # @param block [Block] サニタイズ処理ブロック
    # @return [Object] ブロックの戻り値
    def monitor_sanitization(job_class, args_count, &block)
      start_time = Time.current
      start_memory = current_memory_usage

      begin
        result = yield

        end_time = Time.current
        end_memory = current_memory_usage
        duration = end_time - start_time
        memory_used = end_memory - start_memory

        sanitization_performance = {
          job_class: job_class,
          args_count: args_count,
          duration: duration,
          memory_used: memory_used,
          success: true,
          timestamp: start_time
        }

        # サニタイズ固有の警告チェック
        check_sanitization_warnings(sanitization_performance)

        # 統計更新
        update_sanitization_statistics(sanitization_performance)

        Rails.logger.debug({
          event: "sanitization_performance",
          **sanitization_performance.except(:timestamp).merge(
            timestamp: start_time.iso8601,
            duration_ms: (duration * 1000).round(3),
            memory_used_kb: (memory_used / 1024.0).round(2)
          )
        }.to_json) if debug_mode?

        result

      rescue => e
        end_time = Time.current
        end_memory = current_memory_usage
        duration = end_time - start_time
        memory_used = end_memory - start_memory

        sanitization_error = {
          job_class: job_class,
          args_count: args_count,
          duration: duration,
          memory_used: memory_used,
          success: false,
          error_class: e.class.name,
          error_message: e.message,
          timestamp: start_time
        }

        update_sanitization_statistics(sanitization_error)

        Rails.logger.warn({
          event: "sanitization_performance_error",
          **sanitization_error.except(:timestamp).merge(
            timestamp: start_time.iso8601,
            duration_ms: (duration * 1000).round(3)
          )
        }.to_json)

        raise
      end
    end

    # 現在のパフォーマンス統計取得
    #
    # @param hours [Integer] 過去何時間分の統計を取得するか
    # @return [Hash] 統計データ
    def get_performance_stats(hours: 1)
      {
        job_performance: get_job_performance_stats(hours),
        sanitization_performance: get_sanitization_performance_stats(hours),
        system_performance: get_system_performance_stats,
        alerts: get_recent_alerts(hours)
      }
    end

    # パフォーマンスレポート生成
    #
    # @param format [Symbol] レポート形式 (:json, :csv, :html)
    # @return [String] レポートデータ
    def generate_performance_report(format: :json)
      stats = get_performance_stats(hours: 24)

      case format
      when :json
        stats.to_json
      when :csv
        generate_csv_report(stats)
      when :html
        generate_html_report(stats)
      else
        raise ArgumentError, "Unsupported format: #{format}"
      end
    end

    private

    # ============================================
    # メモリ・システム監視
    # ============================================

    def current_memory_usage
      # プロセスのRSSメモリ使用量を取得
      if RUBY_PLATFORM.include?("darwin")  # macOS
        `ps -o rss= -p #{Process.pid}`.to_i * 1024  # KB to bytes
      elsif RUBY_PLATFORM.include?("linux")  # Linux
        `ps -o rss= -p #{Process.pid}`.to_i * 1024  # KB to bytes
      else
        # フォールバック: GC統計を使用
        GC.stat[:heap_allocated_pages] * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_SIZE]
      end
    rescue
      # エラー時は0を返す（監視の失敗でアプリケーションを止めない）
      0
    end

    def get_cpu_usage
      # CPU使用率の取得（簡易版）
      return 0.0 unless File.exist?("/proc/#{Process.pid}/stat")

      stat_data = File.read("/proc/#{Process.pid}/stat").split
      utime = stat_data[13].to_f
      stime = stat_data[14].to_f

      # 前回の測定値と比較してCPU使用率を計算
      # 簡易実装のため、詳細な計算は省略
      ((utime + stime) / 100.0).round(2)
    rescue
      0.0
    end

    # ============================================
    # Redis データ管理
    # ============================================

    def redis_client
      @redis_client ||= begin
        if defined?(Redis) && Rails.application.config.respond_to?(:redis)
          Rails.application.config.redis
        else
          # フォールバック: インメモリストレージ
          @memory_store ||= {}
        end
      end
    end

    def store_monitoring_start(data)
      key = "#{REDIS_KEY_PREFIX}:active:#{data[:job_id]}"

      if redis_client.is_a?(Hash)
        # インメモリストレージの場合
        redis_client[key] = data.to_json
      else
        # Redis の場合
        redis_client.setex(key, 3600, data.to_json)  # 1時間で自動削除
      end
    rescue => e
      Rails.logger.warn "Failed to store monitoring data: #{e.message}"
    end

    def cleanup_monitoring_data(job_id)
      key = "#{REDIS_KEY_PREFIX}:active:#{job_id}"

      if redis_client.is_a?(Hash)
        redis_client.delete(key)
      else
        redis_client.del(key)
      end
    rescue => e
      Rails.logger.warn "Failed to cleanup monitoring data: #{e.message}"
    end

    # ============================================
    # 統計データ管理
    # ============================================

    def update_performance_statistics(result)
      stats_key = "#{REDIS_KEY_PREFIX}:stats:#{Date.current.strftime('%Y%m%d')}"

      stats_data = {
        job_class: result[:job_class],
        duration: result[:duration],
        memory_delta: result[:memory_delta],
        success: result[:success],
        timestamp: result[:start_time].to_i
      }

      # 統計データをリストに追加
      store_statistics(stats_key, stats_data)
    end

    def update_sanitization_statistics(result)
      stats_key = "#{REDIS_KEY_PREFIX}:sanitization:#{Date.current.strftime('%Y%m%d')}"

      store_statistics(stats_key, result)
    end

    def store_statistics(key, data)
      if redis_client.is_a?(Hash)
        # インメモリストレージの場合
        redis_client[key] ||= []
        redis_client[key] << data

        # サイズ制限（最新1000件まで保持）
        redis_client[key] = redis_client[key].last(1000) if redis_client[key].size > 1000
      else
        # Redis の場合
        redis_client.lpush(key, data.to_json)
        redis_client.ltrim(key, 0, 999)  # 最新1000件まで保持
        redis_client.expire(key, 86400 * 7)  # 7日間保持
      end
    rescue => e
      Rails.logger.warn "Failed to store statistics: #{e.message}"
    end

    # ============================================
    # 警告・アラート
    # ============================================

    def check_performance_warnings(result)
      warnings = []

      # 処理時間チェック
      if result[:duration] > PERFORMANCE_THRESHOLDS[:very_slow_job_threshold]
        warnings << {
          type: :critical,
          category: :duration,
          message: "Very slow job detected: #{result[:duration].round(2)}s",
          threshold: PERFORMANCE_THRESHOLDS[:very_slow_job_threshold]
        }
      elsif result[:duration] > PERFORMANCE_THRESHOLDS[:slow_job_threshold]
        warnings << {
          type: :warning,
          category: :duration,
          message: "Slow job detected: #{result[:duration].round(2)}s",
          threshold: PERFORMANCE_THRESHOLDS[:slow_job_threshold]
        }
      end

      # メモリ使用量チェック
      if result[:memory_delta] > PERFORMANCE_THRESHOLDS[:memory_critical_threshold]
        warnings << {
          type: :critical,
          category: :memory,
          message: "Critical memory usage: #{(result[:memory_delta] / 1.megabyte).round(2)}MB",
          threshold: PERFORMANCE_THRESHOLDS[:memory_critical_threshold]
        }
      elsif result[:memory_delta] > PERFORMANCE_THRESHOLDS[:memory_warning_threshold]
        warnings << {
          type: :warning,
          category: :memory,
          message: "High memory usage: #{(result[:memory_delta] / 1.megabyte).round(2)}MB",
          threshold: PERFORMANCE_THRESHOLDS[:memory_warning_threshold]
        }
      end

      # 警告がある場合はアラート送信
      send_performance_alerts(result, warnings) if warnings.any?
    end

    def check_sanitization_warnings(result)
      warnings = []

      if result[:duration] > PERFORMANCE_THRESHOLDS[:sanitization_time_limit]
        warnings << {
          type: :warning,
          category: :sanitization_time,
          message: "Slow sanitization: #{(result[:duration] * 1000).round(2)}ms",
          threshold: PERFORMANCE_THRESHOLDS[:sanitization_time_limit]
        }
      end

      if result[:memory_used] > PERFORMANCE_THRESHOLDS[:sanitization_memory_limit]
        warnings << {
          type: :warning,
          category: :sanitization_memory,
          message: "High sanitization memory: #{(result[:memory_used] / 1.megabyte).round(2)}MB",
          threshold: PERFORMANCE_THRESHOLDS[:sanitization_memory_limit]
        }
      end

      send_sanitization_alerts(result, warnings) if warnings.any?
    end

    def send_performance_alerts(result, warnings)
      alert_data = {
        event: "performance_alert",
        job_class: result[:job_class],
        job_id: result[:job_id],
        warnings: warnings,
        performance_data: result.slice(:duration, :memory_delta, :success),
        timestamp: Time.current.iso8601
      }

      Rails.logger.warn(alert_data.to_json)

      # 外部アラート送信（設定されている場合）
      send_external_alert(alert_data) if alert_enabled?
    end

    def send_sanitization_alerts(result, warnings)
      alert_data = {
        event: "sanitization_alert",
        job_class: result[:job_class],
        warnings: warnings,
        sanitization_data: result.slice(:duration, :memory_used, :args_count),
        timestamp: Time.current.iso8601
      }

      Rails.logger.warn(alert_data.to_json)

      send_external_alert(alert_data) if alert_enabled?
    end

    def send_external_alert(alert_data)
      # Slack、Teams、メール等の外部通知
      # 実装は設定に依存

      if webhook_url = Rails.application.config.secure_job_alerts&.dig(:slack_webhook)
        send_slack_alert(webhook_url, alert_data)
      end

      if email = Rails.application.config.secure_job_alerts&.dig(:alert_email)
        send_email_alert(email, alert_data)
      end
    rescue => e
      Rails.logger.error "Failed to send external alert: #{e.message}"
    end

    # ============================================
    # 統計取得・レポート生成
    # ============================================

    def get_job_performance_stats(hours)
      # 過去指定時間のジョブパフォーマンス統計
      {
        total_jobs: 0,  # 実装省略
        average_duration: 0.0,
        max_duration: 0.0,
        average_memory: 0,
        success_rate: 100.0,
        slow_jobs_count: 0
      }
    end

    def get_sanitization_performance_stats(hours)
      # 過去指定時間のサニタイズパフォーマンス統計
      {
        total_sanitizations: 0,  # 実装省略
        average_duration: 0.0,
        average_memory: 0,
        success_rate: 100.0
      }
    end

    def get_system_performance_stats
      {
        current_memory: current_memory_usage,
        cpu_usage: get_cpu_usage,
        active_jobs: get_active_jobs_count,
        timestamp: Time.current.iso8601
      }
    end

    def get_recent_alerts(hours)
      # 過去指定時間のアラート履歴
      []
    end

    def get_active_jobs_count
      # アクティブなジョブ数の取得
      if redis_client.is_a?(Hash)
        redis_client.keys("#{REDIS_KEY_PREFIX}:active:*").size
      else
        redis_client.keys("#{REDIS_KEY_PREFIX}:active:*").size
      end
    rescue
      0
    end

    # ============================================
    # ヘルパーメソッド
    # ============================================

    def debug_mode?
      Rails.application.config.secure_job_logging&.dig(:debug_mode) || Rails.env.development?
    end

    def alert_enabled?
      Rails.application.config.secure_job_alerts&.dig(:enable_security_alerts) || false
    end

    def send_slack_alert(webhook_url, alert_data)
      # Slack通知の実装
      # TODO: 実際のWebhook送信実装
    end

    def send_email_alert(email, alert_data)
      # メール通知の実装
      # TODO: ActionMailer連携実装
    end

    def generate_csv_report(stats)
      # CSV形式のレポート生成
      # TODO: CSV生成実装
      ""
    end

    def generate_html_report(stats)
      # HTML形式のレポート生成
      # TODO: HTML生成実装
      ""
    end
  end
end
