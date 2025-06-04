# frozen_string_literal: true

# ============================================
# Security Monitor System
# ============================================
# セキュリティ監視・異常検知システム
# REF: doc/remaining_tasks.md - エラー追跡・分析（優先度：高）

class SecurityMonitor
  include Singleton

  # ============================================
  # 設定値・定数
  # ============================================

  # 異常アクセスパターンの閾値
  SuspiciousThreshold = Struct.new(:rapid_requests, :failed_logins, :unique_user_agents, :request_size, :response_time) do
    def self.default
      new(
        100,            # 1分間のリクエスト数
        5,              # 連続ログイン失敗数
        10,             # 異なるUser-Agentの数（同一IP）
        10.megabytes,   # 異常に大きなリクエストサイズ
        30.seconds      # 異常に遅いレスポンス時間
      )
    end
  end

  # ブロック期間（分）
  BlockDuration = Struct.new(:suspicious_ip, :brute_force, :sql_injection, :path_traversal) do
    def self.default_minutes
      new(
        60,             # 疑わしいIP
        120,            # ブルートフォース攻撃
        1440,           # SQLインジェクション試行（24時間）
        720             # パストラバーサル攻撃（12時間）
      )
    end
  end

  SUSPICIOUS_THRESHOLDS = SuspiciousThreshold.default.freeze
  BLOCK_DURATIONS = BlockDuration.default_minutes.freeze

  # ============================================
  # 異常アクセスパターンの検出
  # ============================================

  def self.analyze_request(request, response = nil)
    instance.analyze_request(request, response)
  end

  def analyze_request(request, response = nil)
    client_ip = extract_client_ip(request)
    user_agent = request.user_agent
    request_path = request.path

    # 各種パターン検知を実行
    patterns_detected = []

    patterns_detected << :rapid_requests if rapid_requests_detected?(client_ip)
    patterns_detected << :suspicious_user_agent if suspicious_user_agent?(user_agent)
    patterns_detected << :path_traversal if path_traversal_attempt?(request_path)
    patterns_detected << :sql_injection if sql_injection_attempt?(request)
    patterns_detected << :large_request if large_request?(request)

    # 異常パターンが検出された場合の処理
    if patterns_detected.any?
      handle_suspicious_activity(client_ip, patterns_detected, {
        request_path: request_path,
        user_agent: user_agent,
        referer: request.referer,
        request_method: request.request_method
      })
    end

    # リクエスト統計の更新
    update_request_statistics(client_ip, user_agent, request_path)

    patterns_detected
  end

  # ============================================
  # ログイン試行の監視
  # ============================================

  def self.track_login_attempt(ip_address, email, success:, user_agent: nil)
    instance.track_login_attempt(ip_address, email, success: success, user_agent: user_agent)
  end

  def track_login_attempt(ip_address, email, success:, user_agent: nil)
    redis = get_redis_connection
    return unless redis

    key = "login_attempts:#{ip_address}"
    failed_key = "failed_logins:#{ip_address}:#{email}"

    if success
      # 成功時：失敗カウントをリセット
      redis.del(failed_key)
      log_security_event(:successful_login, {
        ip_address: ip_address,
        email: email,
        user_agent: user_agent
      })
    else
      # 失敗時：カウント増加
      failed_count = redis.incr(failed_key)
      redis.expire(failed_key, 3600) # 1時間後にリセット

      # ブルートフォース攻撃の検出
      if failed_count >= SUSPICIOUS_THRESHOLDS[:failed_logins]
        handle_brute_force_attack(ip_address, email, failed_count, user_agent)
      end

      log_security_event(:failed_login, {
        ip_address: ip_address,
        email: email,
        failed_count: failed_count,
        user_agent: user_agent
      })
    end
  end

  # ============================================
  # 自動ブロック機能
  # ============================================

  def self.is_blocked?(ip_address)
    instance.is_blocked?(ip_address)
  end

  def is_blocked?(ip_address)
    redis = get_redis_connection
    return false unless redis

    blocked_keys = redis.keys("blocked:*:#{ip_address}")
    blocked_keys.any? { |key| redis.exists?(key) }
  end

  def block_ip(ip_address, reason, duration_minutes = nil)
    redis = get_redis_connection
    return unless redis

    duration = duration_minutes || BLOCK_DURATIONS[reason] || 60
    block_key = "blocked:#{reason}:#{ip_address}"

    redis.setex(block_key, duration * 60, {
      blocked_at: Time.current.iso8601,
      reason: reason,
      duration_minutes: duration
    }.to_json)

    # ブロック通知
    notify_security_event(:ip_blocked, {
      ip_address: ip_address,
      reason: reason,
      duration_minutes: duration,
      blocked_until: (Time.current + duration.minutes).iso8601
    })

    Rails.logger.warn "IP blocked: #{ip_address} (reason: #{reason}, duration: #{duration}min)"
  end

  private

  # ============================================
  # 内部メソッド - 検出ロジック
  # ============================================

  def rapid_requests_detected?(ip_address)
    redis = get_redis_connection
    return false unless redis

    key = "request_count:#{ip_address}"
    count = redis.incr(key)
    redis.expire(key, 60) if count == 1  # 1分間のウィンドウ

    count > SUSPICIOUS_THRESHOLDS[:rapid_requests]
  end

  def suspicious_user_agent?(user_agent)
    return true if user_agent.blank?

    # 既知の攻撃ツールのパターン
    suspicious_patterns = [
      /sqlmap/i, /nikto/i, /nmap/i, /masscan/i,
      /burpsuite/i, /owasp/i, /w3af/i,
      /bot/i, /crawler/i, /scanner/i,
      /<script>/i, /\'\s*OR\s*1=1/i  # 明らかな攻撃パターン
    ]

    suspicious_patterns.any? { |pattern| user_agent.match?(pattern) }
  end

  def path_traversal_attempt?(path)
    # パストラバーサル攻撃のパターン検出
    traversal_patterns = [
      /\.\.[\/\\]/,           # ../
      /%2e%2e[%2f%5c]/i,     # URL エンコードされた ../
      /\/(etc|proc|sys|var)\//i, # Linux システムディレクトリ
      /[\/\\](windows|winnt)[\/\\]/i, # Windows システムディレクトリ
      /\.(conf|passwd|shadow|key|pem)$/i # 設定ファイル
    ]

    traversal_patterns.any? { |pattern| path.match?(pattern) }
  end

  def sql_injection_attempt?(request)
    # SQLインジェクション攻撃のパターン検出
    injection_patterns = [
      /(\s|^)(select|insert|update|delete|drop|create|alter)\s/i,
      /(\s|^)(union|where|having|order\s+by)\s/i,
      /(\s|^)(and|or)\s+1\s*=\s*1/i,
      /\'[\s]*or[\s]*\'.*\'[\s]*=[\s]*\'/i,
      /\"\s*or\s*\"\s*=\s*\"/i,
      /-{2,}/, # SQL コメント
      /\/\*.*\*\// # SQL コメント
    ]

    query_string = request.query_string
    request_body = extract_request_body(request)

    content_to_check = [ query_string, request_body, request.path ].compact.join(" ")

    injection_patterns.any? { |pattern| content_to_check.match?(pattern) }
  end

  def large_request?(request)
    content_length = request.content_length
    return false unless content_length

    content_length > SUSPICIOUS_THRESHOLDS[:request_size]
  end

  # ============================================
  # 内部メソッド - 対応処理
  # ============================================

  def handle_suspicious_activity(ip_address, patterns, request_details)
    severity = determine_severity(patterns)

    # 重大度に応じた対応
    case severity
    when :critical
      block_ip(ip_address, :critical_threat, BLOCK_DURATIONS[:sql_injection])
    when :high
      block_ip(ip_address, :high_threat, BLOCK_DURATIONS[:brute_force])
    when :medium
      # 警告ログのみ（ブロックしない）
      log_security_event(:suspicious_activity, {
        ip_address: ip_address,
        patterns: patterns,
        severity: severity,
        **request_details
      })
    end

    # セキュリティチームへの通知
    notify_security_event(:suspicious_activity_detected, {
      ip_address: ip_address,
      patterns: patterns,
      severity: severity,
      action_taken: severity == :medium ? "logged" : "blocked",
      **request_details
    })
  end

  def handle_brute_force_attack(ip_address, email, failed_count, user_agent)
    block_ip(ip_address, :brute_force, BLOCK_DURATIONS[:brute_force])

    # 緊急通知
    notify_security_event(:brute_force_detected, {
      ip_address: ip_address,
      email: email,
      failed_count: failed_count,
      user_agent: user_agent,
      blocked_duration: BLOCK_DURATIONS[:brute_force]
    })
  end

  def determine_severity(patterns)
    return :critical if patterns.include?(:sql_injection) || patterns.include?(:path_traversal)
    return :high if patterns.include?(:rapid_requests) && patterns.length > 1
    :medium
  end

  # ============================================
  # 内部メソッド - ユーティリティ
  # ============================================

  def extract_client_ip(request)
    # リバースプロキシ経由の場合のIPアドレス取得
    request.env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
    request.env["HTTP_X_REAL_IP"] ||
    request.remote_ip
  end

  def extract_request_body(request)
    return nil unless request.content_length && request.content_length > 0
    return nil if request.content_length > 1.megabyte  # 大きすぎる場合はスキップ

    begin
      request.body.read(1.megabyte)  # 最大1MBまで読み取り
    rescue => e
      Rails.logger.warn "Failed to read request body: #{e.message}"
      nil
    ensure
      request.body.rewind if request.body.respond_to?(:rewind)
    end
  end

  def update_request_statistics(ip_address, user_agent, path)
    redis = get_redis_connection
    return unless redis

    # 時間別統計
    hour_key = "stats:requests:#{Time.current.strftime('%Y%m%d%H')}"
    redis.incr(hour_key)
    redis.expire(hour_key, 25.hours.to_i)

    # IP別統計
    ip_key = "stats:ip:#{ip_address}:#{Date.current.strftime('%Y%m%d')}"
    redis.incr(ip_key)
    redis.expire(ip_key, 2.days.to_i)
  end

  def get_redis_connection
    # ProgressNotifierと同じロジックを使用
    if Rails.env.test?
      return nil unless defined?(Redis)

      begin
        redis = Redis.current
        redis.ping
        return redis
      rescue => e
        Rails.logger.warn "Redis not available in test environment: #{e.message}"
        return nil
      end
    end

    begin
      if defined?(Sidekiq) && Sidekiq.redis_pool
        Sidekiq.redis { |conn| return conn }
      else
        Redis.current
      end
    rescue => e
      Rails.logger.warn "Redis connection failed: #{e.message}"
      nil
    end
  end

  def log_security_event(event_type, details)
    Rails.logger.info({
      event: "security_#{event_type}",
      timestamp: Time.current.iso8601,
      **details
    }.to_json)
  end

  def notify_security_event(event_type, details)
    # TODO: 実際の通知システム（Slack、メール等）との連携
    # AdminNotificationService.security_alert(event_type, details)

    Rails.logger.warn({
      event: "security_notification",
      notification_type: event_type,
      timestamp: Time.current.iso8601,
      **details
    }.to_json)
  end
end

# ============================================
# TODO: セキュリティ監視システムの拡張計画（優先度：高）
# REF: doc/remaining_tasks.md - エラー追跡・分析
# ============================================
# 1. 機械学習による異常検知（優先度：中）
#    - 正常なアクセスパターンの学習
#    - 異常スコアの自動計算
#    - 偽陽性の削減
#
# 2. 脅威インテリジェンス連携（優先度：高）
#    - 既知の悪意あるIPリストとの照合
#    - 外部脅威データベースとの連携
#    - リアルタイム脅威情報の取得
#
# 3. 可視化・ダッシュボード（優先度：中）
#    - セキュリティ状況のリアルタイム表示
#    - 攻撃マップの可視化
#    - トレンド分析とレポート生成
#
# 4. 自動対応・隔離機能（優先度：高）
#    - 段階的な対応レベル
#    - 自動隔離とエスカレーション
#    - 復旧手順の自動化
#
# 5. コンプライアンス対応（優先度：中）
#    - セキュリティログの長期保存
#    - 監査レポートの自動生成
#    - 規制要件への準拠確認
