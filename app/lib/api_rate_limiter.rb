# frozen_string_literal: true

# APIレート制限機能
# CLAUDE.md準拠: API保護とパフォーマンス維持のためのレート制限実装
class ApiRateLimiter
  # レート制限設定
  LIMITS = {
    # 認証なしユーザー
    anonymous: {
      requests_per_hour: 60,
      requests_per_minute: 10
    },
    # 認証済みユーザー
    authenticated: {
      requests_per_hour: 600,
      requests_per_minute: 60
    },
    # プレミアムユーザー（将来実装）
    premium: {
      requests_per_hour: 6000,
      requests_per_minute: 200
    }
  }.freeze

  # エラーメッセージテンプレート
  ERROR_MESSAGES = {
    hourly_limit: "1時間あたりのAPIリクエスト上限（%{limit}回）を超えました",
    minute_limit: "1分あたりのAPIリクエスト上限（%{limit}回）を超えました"
  }.freeze

  attr_reader :redis, :identifier, :user_type

  def initialize(identifier:, user_type: :anonymous, redis: nil)
    @identifier = identifier
    @user_type = user_type.to_sym
    @redis = redis || Redis.current
  end

  # レート制限チェック
  # @return [Hash] { allowed: Boolean, remaining: Integer, reset_at: Time, retry_after: Integer }
  def check_limit
    hourly_check = check_hourly_limit
    minute_check = check_minute_limit

    # どちらかの制限に引っかかった場合
    if !hourly_check[:allowed] || !minute_check[:allowed]
      limited_check = hourly_check[:allowed] ? minute_check : hourly_check
      return {
        allowed: false,
        remaining: limited_check[:remaining],
        reset_at: limited_check[:reset_at],
        retry_after: limited_check[:retry_after],
        limit_type: limited_check[:limit_type],
        message: limited_check[:message]
      }
    end

    # 両方の制限をクリアした場合
    {
      allowed: true,
      remaining: [hourly_check[:remaining], minute_check[:remaining]].min,
      reset_at: [hourly_check[:reset_at], minute_check[:reset_at]].max,
      retry_after: nil,
      hourly_remaining: hourly_check[:remaining],
      minute_remaining: minute_check[:remaining]
    }
  end

  # リクエストを記録
  def track_request
    increment_counter(hourly_key, 3600) # 1時間
    increment_counter(minute_key, 60)   # 1分
  end

  # 使用状況を取得
  def usage_info
    {
      hourly: {
        used: get_counter(hourly_key),
        limit: limits[:requests_per_hour],
        remaining: limits[:requests_per_hour] - get_counter(hourly_key),
        reset_at: Time.current + ttl(hourly_key).seconds
      },
      minute: {
        used: get_counter(minute_key),
        limit: limits[:requests_per_minute],
        remaining: limits[:requests_per_minute] - get_counter(minute_key),
        reset_at: Time.current + ttl(minute_key).seconds
      }
    }
  end

  # レート制限をリセット（テスト・管理用）
  def reset!
    redis.del(hourly_key, minute_key)
  end

  # レスポンスヘッダーを生成
  def headers_for_response(check_result)
    headers = {
      "X-RateLimit-Limit-Hour" => limits[:requests_per_hour].to_s,
      "X-RateLimit-Limit-Minute" => limits[:requests_per_minute].to_s,
      "X-RateLimit-Remaining" => check_result[:remaining].to_s,
      "X-RateLimit-Reset" => check_result[:reset_at].to_i.to_s
    }

    if check_result[:retry_after]
      headers["Retry-After"] = check_result[:retry_after].to_s
    end

    headers
  end

  private

  def limits
    LIMITS[user_type] || LIMITS[:anonymous]
  end

  def hourly_key
    "api_rate_limit:hourly:#{identifier}"
  end

  def minute_key
    "api_rate_limit:minute:#{identifier}"
  end

  def check_hourly_limit
    count = get_counter(hourly_key)
    limit = limits[:requests_per_hour]
    remaining = [limit - count, 0].max
    reset_at = Time.current + ttl(hourly_key).seconds

    {
      allowed: count < limit,
      remaining: remaining,
      reset_at: reset_at,
      retry_after: remaining.zero? ? ttl(hourly_key) : nil,
      limit_type: :hourly,
      message: ERROR_MESSAGES[:hourly_limit] % { limit: limit }
    }
  end

  def check_minute_limit
    count = get_counter(minute_key)
    limit = limits[:requests_per_minute]
    remaining = [limit - count, 0].max
    reset_at = Time.current + ttl(minute_key).seconds

    {
      allowed: count < limit,
      remaining: remaining,
      reset_at: reset_at,
      retry_after: remaining.zero? ? ttl(minute_key) : nil,
      limit_type: :minute,
      message: ERROR_MESSAGES[:minute_limit] % { limit: limit }
    }
  end

  def get_counter(key)
    redis.get(key).to_i
  end

  def increment_counter(key, ttl_seconds)
    redis.multi do |r|
      r.incr(key)
      r.expire(key, ttl_seconds)
    end
  end

  def ttl(key)
    remaining = redis.ttl(key)
    remaining.positive? ? remaining : 0
  end
end