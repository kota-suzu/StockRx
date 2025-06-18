# frozen_string_literal: true

# レート制限サービス
# ============================================
# Phase 5-1: セキュリティ強化
# ブルートフォース攻撃やDoS攻撃を防ぐためのレート制限
# CLAUDE.md準拠: セキュリティ最優先
# ============================================
class RateLimiter
  LIMITS = {
    # ログイン試行
    login: {
      limit: 5,
      period: 15.minutes,
      block_duration: 30.minutes
    },
    # パスワードリセット
    password_reset: {
      limit: 3,
      period: 1.hour,
      block_duration: 1.hour
    },
    # メール認証（パスコード送信）
    # メタ認知: EmailAuthServiceの設定と整合性を保つ（3回/時間、10回/日）
    # 横展開: password_resetと同様のセキュリティレベル
    email_auth: {
      limit: 3,
      period: 1.hour,
      block_duration: 1.hour
    },
    # API呼び出し
    api: {
      limit: 100,
      period: 1.hour,
      block_duration: 1.hour
    },
    # 店舗間移動申請
    transfer_request: {
      limit: 20,
      period: 1.day,
      block_duration: 1.hour
    },
    # ファイルアップロード
    file_upload: {
      limit: 10,
      period: 1.hour,
      block_duration: 30.minutes
    }
  }.freeze

  def initialize(key_type, identifier)
    @key_type = key_type
    @identifier = identifier
    @config = LIMITS[@key_type] || raise(ArgumentError, "Unknown rate limit type: #{@key_type}")
  end

  # レート制限チェック
  def allowed?
    return false if blocked?

    current_count < @config[:limit]
  end

  # アクションを記録
  def track!
    return false if blocked?

    increment_counter!

    # 制限に達した場合はブロック
    if current_count >= @config[:limit]
      block!
      false
    else
      true
    end
  end

  # 現在のカウント
  def current_count
    redis.get(counter_key).to_i
  end

  # 残り試行回数
  def remaining_attempts
    [ @config[:limit] - current_count, 0 ].max
  end

  # ブロックされているか
  def blocked?
    redis.exists?(block_key)
  end

  # ブロック解除までの時間（秒）
  def time_until_unblock
    return 0 unless blocked?

    ttl = redis.ttl(block_key)
    ttl > 0 ? ttl : 0
  end

  # 手動でリセット（管理者用）
  def reset!
    redis.del(counter_key)
    redis.del(block_key)
  end

  private

  def redis
    @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
  end

  def counter_key
    "rate_limit:#{@key_type}:#{@identifier}:count"
  end

  def block_key
    "rate_limit:#{@key_type}:#{@identifier}:blocked"
  end

  def increment_counter!
    redis.multi do |r|
      r.incr(counter_key)
      r.expire(counter_key, @config[:period].to_i)
    end
  end

  def block!
    redis.setex(block_key, @config[:block_duration].to_i, "1")

    # ブロックイベントをログに記録
    Rails.logger.warn({
      event: "rate_limit_exceeded",
      key_type: @key_type,
      identifier: @identifier,
      timestamp: Time.current.iso8601
    }.to_json)

    # Phase 5-2 - 監査ログへの記録
    begin
      AuditLog.log_action(
        nil,  # auditable は nil（システムイベント）
        "security_event",
        "レート制限超過: #{@key_type}",
        {
          event_type: "rate_limit_exceeded",
          key_type: @key_type,
          identifier: @identifier,
          limit: @config[:limit],
          period: @config[:period],
          block_duration: @config[:block_duration],
          severity: "warning"
        }
      )
    rescue => e
      Rails.logger.error "監査ログ記録失敗: #{e.message}"
    end
  end
end

# ============================================
# 使用例:
# ============================================
# # ログイン試行のレート制限
# limiter = RateLimiter.new(:login, request.remote_ip)
# unless limiter.allowed?
#   render json: {
#     error: 'Too many login attempts',
#     retry_after: limiter.time_until_unblock
#   }, status: :too_many_requests
#   return
# end
#
# # ログイン処理...
# if login_failed?
#   limiter.track!
# end
