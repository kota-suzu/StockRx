# frozen_string_literal: true

# Rack::Attack設定
# ================
# DDoS攻撃、ブルートフォース攻撃対策
# レート制限、IP制限、セキュリティ監視
# ================

# テスト環境では無効化
return if Rails.env.test?

# Rack::Attackが利用可能かチェック
unless defined?(Rack::Attack)
  Rails.logger.warn "Rack::Attack not available, skipping configuration"
  return
end

# Redis設定（Sidekiqと共有）
Rack::Attack.cache.store = ActiveSupport::Cache::RedisCache.new(
  url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
  namespace: "rack_attack"
)

# セーフリスト（ホワイトリスト）
Rack::Attack.safelist("allow-localhost") do |req|
  # 開発環境のlocalhost許可
  Rails.env.development? && [ "127.0.0.1", "::1" ].include?(req.ip)
end

Rack::Attack.safelist("allow-health-checks") do |req|
  # ヘルスチェックエンドポイント許可
  req.path.start_with?("/health") || req.path.start_with?("/status")
end

# ブロックリスト（ブラックリスト）
Rack::Attack.blocklist("block-bad-bots") do |req|
  # 悪意のあるUser-Agentをブロック
  user_agent = req.get_header("HTTP_USER_AGENT")
  user_agent && user_agent.match(/sqlmap|nikto|netsparker|masscan|nmap/i)
end

Rack::Attack.blocklist("block-sql-injection-attempts") do |req|
  # SQLインジェクション試行をブロック
  suspicious_patterns = [
    /(\%27)|(\')|(\-\-)|(\%23)|(#)/i,  # SQL injection patterns
    /((\%3D)|(=))[^\n]*((\%27)|(\')|(\-\-)|(\%3B)|(;))/i,
    /\w*((\%27)|(\'))((\%6F)|o|(\%4F))((\%72)|r|(\%52))/i,
    /((\%27)|(\'))union/i
  ]

  request_params = req.params.values.join(" ")
  request_path = req.path
  query_string = req.query_string

  suspicious_patterns.any? do |pattern|
    request_params.match(pattern) ||
    request_path.match(pattern) ||
    query_string.match(pattern)
  end
end

# スロットリング（レート制限）設定

# 1. 全般的なレート制限
Rack::Attack.throttle("requests by ip", limit: 300, period: 5.minutes) do |req|
  req.ip unless req.path.start_with?("/assets") # 静的ファイルは除外
end

# 2. ログイン試行制限（ブルートフォース対策）
Rack::Attack.throttle("login attempts by ip", limit: 5, period: 15.minutes) do |req|
  if req.path == "/admin/sign_in" && req.post?
    req.ip
  end
end

Rack::Attack.throttle("login attempts by email", limit: 3, period: 15.minutes) do |req|
  if req.path == "/admin/sign_in" && req.post?
    email = req.params.dig("admin", "email") || req.params["email"]
    email.to_s.downcase.gsub(/\s+/, "") if email.present?
  end
end

# 3. パスワードリセット制限
Rack::Attack.throttle("password reset by ip", limit: 3, period: 1.hour) do |req|
  if req.path == "/admin/password" && req.post?
    req.ip
  end
end

# 4. API制限（将来のAPI実装時）
Rack::Attack.throttle("api requests", limit: 1000, period: 1.hour) do |req|
  if req.path.start_with?("/api/")
    # APIキー認証時は緩い制限
    api_key = req.get_header("X-API-KEY")
    if api_key.present?
      "api_key:#{api_key}"
    else
      # 未認証APIは厳しい制限
      "api_ip:#{req.ip}"
    end
  end
end

# 5. 重要操作の制限
Rack::Attack.throttle("sensitive operations by ip", limit: 10, period: 1.hour) do |req|
  sensitive_paths = [
    "/admin/inventories/import",
    "/admin/inventories/export",
    "/admin/users",
    "/admin/settings"
  ]

  if sensitive_paths.any? { |path| req.path.start_with?(path) } && req.post?
    req.ip
  end
end

# 6. 検索クエリ制限（DoS対策）
Rack::Attack.throttle("search requests by ip", limit: 50, period: 10.minutes) do |req|
  if req.path.include?("search") || req.params["q"].present?
    req.ip
  end
end

# レスポンスカスタマイズ
class Rack::Attack::Request < ::Rack::Request
  # 管理者IPチェック
  def admin_ip?
    admin_ips = ENV.fetch("ADMIN_IPS", "").split(",").map(&:strip)
    admin_ips.include?(ip)
  end

  # 地理的制限（将来実装用）
  def allowed_country?
    # GeoIPライブラリとの統合予定
    true
  end
end

# スロットリング検出時の処理
Rack::Attack.throttled_responder = lambda do |env|
  match_data = env["rack.attack.match_data"]
  now = match_data[:epoch_time]

  headers = {
    "Content-Type" => "application/json",
    "X-RateLimit-Limit" => match_data[:limit].to_s,
    "X-RateLimit-Remaining" => "0",
    "X-RateLimit-Reset" => (now + (match_data[:period] - now % match_data[:period])).to_s,
    "Retry-After" => match_data[:period].to_s
  }

  body = {
    error: "Rate limit exceeded",
    message: "Too many requests. Please try again later.",
    retry_after: match_data[:period]
  }.to_json

  [ 429, headers, [ body ] ]
end

# ブロック検出時の処理
Rack::Attack.blocklisted_responder = lambda do |env|
  headers = {
    "Content-Type" => "application/json"
  }

  body = {
    error: "Access denied",
    message: "Your request has been blocked for security reasons."
  }.to_json

  [ 403, headers, [ body ] ]
end

# 通知設定（本番環境）
if Rails.env.production?
  # Slack通知、メール通知などの設定
  ActiveSupport::Notifications.subscribe("rack.attack") do |name, start, finish, request_id, payload|
    request = payload[:request]

    case name
    when "throttle.rack.attack"
      Rails.logger.warn "[SECURITY] Rate limit exceeded: IP=#{request.ip}, Path=#{request.path}"
    when "blocklist.rack.attack"
      Rails.logger.error "[SECURITY] Request blocked: IP=#{request.ip}, Path=#{request.path}, Reason=#{payload[:discriminator]}"
    end
  end
end

# 開発環境での詳細ログ
if Rails.env.development?
  ActiveSupport::Notifications.subscribe("rack.attack") do |name, start, finish, request_id, payload|
    puts "[Rack::Attack] #{name}: #{payload}"
  end
end
