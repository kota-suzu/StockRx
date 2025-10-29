# frozen_string_literal: true

# Memory Monitor
# =====================================
# 責務: メモリ使用量の監視と制御
# 目的: メモリリークとOOMエラーの防止
# =====================================
class MemoryMonitor
  include ActiveModel::Model

  # メモリ使用量の閾値（MB）
  HIGH_MEMORY_THRESHOLD = 0.8  # 制限の80%で警告
  CRITICAL_MEMORY_THRESHOLD = 0.95  # 制限の95%で緊急対応

  attr_reader :memory_limit_mb, :monitoring_interval

  def initialize(memory_limit_mb, monitoring_interval = 60)
    @memory_limit_mb = memory_limit_mb
    @monitoring_interval = monitoring_interval
    @last_check_time = Time.current
    @memory_history = []
  end

  # 現在のメモリ使用量取得（MB）
  def current_memory_usage
    memory_usage_bytes = get_memory_usage_bytes
    return 0 unless memory_usage_bytes

    (memory_usage_bytes / 1024.0 / 1024.0).round(2)
  end

  # 利用可能メモリ（MB）
  def available_memory_mb
    current_usage = current_memory_usage
    [ @memory_limit_mb - current_usage, 0 ].max
  end

  # メモリ使用量が高いかチェック
  def memory_usage_high?
    usage_ratio = current_memory_usage / @memory_limit_mb
    usage_ratio > HIGH_MEMORY_THRESHOLD
  end

  # メモリ使用量が危険レベルかチェック
  def memory_usage_critical?
    usage_ratio = current_memory_usage / @memory_limit_mb
    usage_ratio > CRITICAL_MEMORY_THRESHOLD
  end

  # メモリ使用率（0.0〜1.0）
  def memory_usage_ratio
    current_memory_usage / @memory_limit_mb
  end

  # 定期的な監視実行
  def check_memory_periodically
    return unless should_check_memory?

    current_usage = current_memory_usage
    record_memory_usage(current_usage)

    if memory_usage_critical?
      handle_critical_memory_usage(current_usage)
    elsif memory_usage_high?
      handle_high_memory_usage(current_usage)
    end

    @last_check_time = Time.current
  end

  # メモリ統計の取得
  def memory_stats
    {
      current_usage_mb: current_memory_usage,
      limit_mb: @memory_limit_mb,
      usage_ratio: memory_usage_ratio.round(3),
      available_mb: available_memory_mb,
      peak_usage_mb: peak_memory_usage,
      average_usage_mb: average_memory_usage,
      memory_trend: memory_trend_analysis
    }
  end

  # メモリリークの検出
  def memory_leak_detected?
    return false if @memory_history.size < 10

    # 過去10回の測定でメモリ使用量が単調増加している場合はリークの可能性
    recent_usage = @memory_history.last(10)

    # 単調増加の確認
    increasing_count = 0
    (1...recent_usage.size).each do |i|
      increasing_count += 1 if recent_usage[i] > recent_usage[i-1]
    end

    # 80%以上が増加傾向の場合はメモリリークと判定
    (increasing_count.to_f / (recent_usage.size - 1)) > 0.8
  end

  private

  # メモリ使用量取得（バイト）
  def get_memory_usage_bytes
    if defined?(ObjectSpace)
      # Ruby ObjectSpace使用
      ObjectSpace.count_objects[:TOTAL] * 40 # 推定サイズ
    elsif system_memory_available?
      # システムコマンド使用
      get_process_memory_usage
    else
      nil
    end
  rescue
    nil
  end

  # プロセスメモリ使用量取得（Linux/macOS）
  def get_process_memory_usage
    if RUBY_PLATFORM.include?("linux")
      # Linux: /proc/self/statusから取得
      status = File.read("/proc/self/status")
      vmrss_line = status.lines.find { |line| line.start_with?("VmRSS:") }
      return nil unless vmrss_line

      vmrss_kb = vmrss_line.split[1].to_i
      vmrss_kb * 1024 # バイトに変換
    elsif RUBY_PLATFORM.include?("darwin")
      # macOS: psコマンド使用
      pid = Process.pid
      result = `ps -o rss= -p #{pid}`.strip
      result.to_i * 1024 # バイトに変換
    else
      nil
    end
  rescue
    nil
  end

  # システムメモリ監視が利用可能か
  def system_memory_available?
    RUBY_PLATFORM.include?("linux") || RUBY_PLATFORM.include?("darwin")
  end

  # 定期チェックが必要か
  def should_check_memory?
    Time.current - @last_check_time >= @monitoring_interval
  end

  # メモリ使用量の記録
  def record_memory_usage(usage_mb)
    @memory_history << {
      timestamp: Time.current,
      usage_mb: usage_mb
    }

    # 履歴のサイズ制限（最新100件まで）
    @memory_history = @memory_history.last(100) if @memory_history.size > 100
  end

  # 高メモリ使用量の処理
  def handle_high_memory_usage(current_usage)
    Rails.logger.warn({
      event: "high_memory_usage_detected",
      current_usage_mb: current_usage,
      limit_mb: @memory_limit_mb,
      usage_ratio: memory_usage_ratio.round(3),
      memory_trend: memory_trend_analysis
    }.to_json)

    # 軽度なメモリ最適化
    suggest_memory_optimization
  end

  # 危険レベルのメモリ使用量の処理
  def handle_critical_memory_usage(current_usage)
    Rails.logger.error({
      event: "critical_memory_usage_detected",
      current_usage_mb: current_usage,
      limit_mb: @memory_limit_mb,
      usage_ratio: memory_usage_ratio.round(3),
      memory_leak_detected: memory_leak_detected?
    }.to_json)

    # 緊急メモリ解放
    perform_emergency_memory_cleanup
  end

  # メモリ最適化の提案
  def suggest_memory_optimization
    Rails.logger.info({
      event: "memory_optimization_suggested",
      suggestions: [
        "Reduce batch size",
        "Perform garbage collection",
        "Clear ActiveRecord connection pool"
      ]
    }.to_json)
  end

  # 緊急メモリクリーンアップ
  def perform_emergency_memory_cleanup
    Rails.logger.warn("Performing emergency memory cleanup")

    # 強制ガベージコレクション
    GC.start

    # ActiveRecordコネクションプールのクリア
    ActiveRecord::Base.clear_active_connections!

    # クリーンアップ後のメモリ使用量をログ
    after_cleanup_usage = current_memory_usage
    Rails.logger.info({
      event: "emergency_memory_cleanup_completed",
      memory_usage_after_cleanup: after_cleanup_usage,
      memory_freed_mb: (current_usage - after_cleanup_usage).round(2)
    }.to_json)
  end

  # ピークメモリ使用量
  def peak_memory_usage
    return 0 if @memory_history.empty?
    @memory_history.map { |entry| entry[:usage_mb] }.max
  end

  # 平均メモリ使用量
  def average_memory_usage
    return 0 if @memory_history.empty?

    total_usage = @memory_history.sum { |entry| entry[:usage_mb] }
    (total_usage / @memory_history.size).round(2)
  end

  # メモリ使用傾向の分析
  def memory_trend_analysis
    return "insufficient_data" if @memory_history.size < 5

    recent_entries = @memory_history.last(5)
    first_usage = recent_entries.first[:usage_mb]
    last_usage = recent_entries.last[:usage_mb]

    trend_ratio = (last_usage - first_usage) / first_usage

    case trend_ratio
    when -Float::INFINITY..-0.1
      "decreasing"
    when -0.1..0.1
      "stable"
    when 0.1..Float::INFINITY
      "increasing"
    else
      "unknown"
    end
  end
end
