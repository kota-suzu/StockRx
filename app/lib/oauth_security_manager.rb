# frozen_string_literal: true

# OAuth Security Manager
# =====================================
# 責務: OAuth認証のセキュリティ強化管理
# 目的: 認証プロセス全体のセキュリティ向上
# =====================================
class OauthSecurityManager
  include ActiveModel::Model

  # セキュリティ設定定数
  CSRF_TOKEN_EXPIRY = 10.minutes
  SESSION_TIMEOUT = 30.minutes
  MAX_LOGIN_ATTEMPTS = 5
  LOCKOUT_DURATION = 15.minutes

  # 許可されたリダイレクトドメイン
  ALLOWED_REDIRECT_DOMAINS = [
    "localhost",
    "127.0.0.1",
    Rails.application.config.force_ssl ? "stockrx.herokuapp.com" : nil
  ].compact.freeze

  attr_reader :request, :session

  def initialize(request, session)
    @request = request
    @session = session
  end

  # OAuth開始前のセキュリティチェック
  def validate_oauth_initiation(provider, redirect_uri = nil)
    results = {
      csrf_token_valid: validate_csrf_token,
      redirect_uri_safe: validate_redirect_uri(redirect_uri),
      rate_limit_ok: check_rate_limit,
      session_secure: validate_session_security,
      provider_allowed: validate_provider(provider)
    }

    log_oauth_initiation(provider, results)

    results.all? { |_, valid| valid }
  end

  # OAuth コールバック後のセキュリティ検証
  def validate_oauth_callback(auth_hash, state_token = nil)
    results = {
      auth_hash_valid: validate_auth_hash(auth_hash),
      state_token_valid: validate_state_token(state_token),
      timing_attack_safe: validate_callback_timing,
      user_info_secure: validate_user_info(auth_hash)
    }

    log_oauth_callback(auth_hash, results)

    results.all? { |_, valid| valid }
  end

  # セキュアなOAuth URLの生成
  def generate_secure_oauth_url(provider, additional_params = {})
    base_url = oauth_provider_url(provider)

    # CSRF保護用のstateトークン生成
    state_token = generate_state_token
    session[:oauth_state_token] = state_token
    session[:oauth_state_expires] = CSRF_TOKEN_EXPIRY.from_now

    # セキュリティパラメータの追加
    security_params = {
      state: state_token,
      redirect_uri: secure_redirect_uri(provider),
      scope: minimal_required_scope(provider)
    }.merge(additional_params)

    build_url_with_params(base_url, security_params)
  end

  # 失敗したログイン試行の記録
  def record_failed_attempt(reason, details = {})
    failure_data = {
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      timestamp: Time.current,
      reason: reason,
      details: details
    }

    session[:failed_oauth_attempts] ||= []
    session[:failed_oauth_attempts] << failure_data

    # 古い記録を削除（最新5件まで保持）
    session[:failed_oauth_attempts] = session[:failed_oauth_attempts].last(5)

    log_security_event("oauth_failed_attempt", failure_data)
  end

  # セッションのセキュアリセット
  def secure_session_reset
    # 古いセッションデータを完全にクリア
    oauth_data = extract_oauth_data
    session.clear

    # 新しいセッションIDを生成
    session.regenerate_id if session.respond_to?(:regenerate_id)

    # 必要な認証データのみを復元
    restore_essential_oauth_data(oauth_data)

    log_security_event("session_reset", { timestamp: Time.current })
  end

  private

  # CSRF トークンの検証
  def validate_csrf_token
    stored_token = session[:oauth_state_token]
    expiry_time = session[:oauth_state_expires]

    return false if stored_token.blank? || expiry_time.blank?
    return false if Time.current > expiry_time

    true
  end

  # リダイレクトURIの安全性検証
  def validate_redirect_uri(redirect_uri)
    return true if redirect_uri.blank? # デフォルトを使用

    begin
      uri = URI.parse(redirect_uri)

      # HTTPSの強制（本番環境）
      if Rails.env.production? && uri.scheme != "https"
        return false
      end

      # 許可されたドメインのチェック
      return false unless ALLOWED_REDIRECT_DOMAINS.include?(uri.host)

      # パスの検証
      return false unless uri.path.start_with?("/admin/auth/")

      true
    rescue URI::InvalidURIError
      false
    end
  end

  # レート制限のチェック
  def check_rate_limit
    cache_key = "oauth_attempts:#{request.remote_ip}"
    attempts = Rails.cache.read(cache_key) || 0

    if attempts >= MAX_LOGIN_ATTEMPTS
      log_security_event("rate_limit_exceeded", {
        ip: request.remote_ip,
        attempts: attempts
      })
      return false
    end

    # 試行回数をインクリメント
    Rails.cache.write(cache_key, attempts + 1, expires_in: LOCKOUT_DURATION)
    true
  end

  # セッションセキュリティの検証
  def validate_session_security
    # セッションのタイムアウトチェック
    if session[:created_at] && Time.current - session[:created_at] > SESSION_TIMEOUT
      return false
    end

    # セッション固定攻撃の防止
    if session[:ip_address] && session[:ip_address] != request.remote_ip
      log_security_event("session_ip_mismatch", {
        stored_ip: session[:ip_address],
        current_ip: request.remote_ip
      })
      return false
    end

    true
  end

  # プロバイダーの検証
  def validate_provider(provider)
    allowed_providers = [ :github ] # 現在はGitHubのみ
    allowed_providers.include?(provider.to_sym)
  end

  # 認証ハッシュの検証
  def validate_auth_hash(auth_hash)
    return false if auth_hash.blank?

    required_fields = %w[provider uid info]
    return false unless required_fields.all? { |field| auth_hash[field].present? }

    # プロバイダー固有の検証
    case auth_hash.provider
    when "github"
      validate_github_auth_hash(auth_hash)
    else
      false
    end
  end

  # GitHub認証ハッシュの検証
  def validate_github_auth_hash(auth_hash)
    return false unless auth_hash.info.email.present?

    # GitHubユーザーIDの形式チェック
    return false unless auth_hash.uid.to_s.match?(/^\d+$/)

    # 最小限必要な情報の存在確認
    required_info = %w[email login name]
    required_info.all? { |field| auth_hash.info[field].present? }
  end

  # ステートトークンの検証
  def validate_state_token(provided_token)
    stored_token = session[:oauth_state_token]
    return false if stored_token.blank? || provided_token.blank?

    # タイミング攻撃対策：一定時間での比較
    secure_compare(stored_token, provided_token)
  end

  # コールバックタイミングの検証
  def validate_callback_timing
    initiation_time = session[:oauth_initiated_at]
    return false if initiation_time.blank?

    elapsed_time = Time.current - initiation_time

    # 極端に早い（自動化された）リクエストを拒否
    return false if elapsed_time < 1.second

    # 極端に遅いリクエストを拒否
    return false if elapsed_time > 10.minutes

    true
  end

  # ユーザー情報のセキュリティ検証
  def validate_user_info(auth_hash)
    email = auth_hash&.info&.email
    return false if email.blank?

    # メールアドレスの形式検証
    return false unless email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)

    # 悪意のあるメールドメインのブロック
    blocked_domains = [ "tempmail.com", "10minutemail.com", "guerrillamail.com" ]
    domain = email.split("@").last&.downcase
    return false if blocked_domains.include?(domain)

    true
  end

  # ステートトークンの生成
  def generate_state_token
    SecureRandom.urlsafe_base64(32)
  end

  # OAuthプロバイダーのURL取得
  def oauth_provider_url(provider)
    case provider
    when :github
      "/admin/auth/github"
    else
      raise ArgumentError, "Unsupported OAuth provider: #{provider}"
    end
  end

  # セキュアなリダイレクトURIの生成
  def secure_redirect_uri(provider)
    protocol = Rails.env.production? ? "https" : request.protocol
    host = request.host_with_port
    "#{protocol}#{host}/admin/auth/#{provider}/callback"
  end

  # 最小限必要なスコープの指定
  def minimal_required_scope(provider)
    case provider
    when :github
      "user:email" # メールアドレスのみ
    else
      ""
    end
  end

  # URLにパラメータを安全に追加
  def build_url_with_params(base_url, params)
    uri = URI.parse(base_url)
    query_params = URI.decode_www_form(uri.query || "")

    params.each do |key, value|
      query_params << [ key.to_s, value.to_s ]
    end

    uri.query = URI.encode_www_form(query_params)
    uri.to_s
  end

  # タイミング攻撃対策の安全な文字列比較
  def secure_compare(a, b)
    return false if a.length != b.length

    result = 0
    a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
    result == 0
  end

  # OAuth データの抽出
  def extract_oauth_data
    {
      provider: session[:omniauth_provider],
      user_id: session[:oauth_user_id],
      verified: session[:oauth_verified]
    }
  end

  # 必要なOAuthデータの復元
  def restore_essential_oauth_data(data)
    session[:omniauth_provider] = data[:provider] if data[:provider]
    session[:oauth_user_id] = data[:user_id] if data[:user_id]
    session[:oauth_verified] = data[:verified] if data[:verified]
    session[:created_at] = Time.current
    session[:ip_address] = request.remote_ip
  end

  # OAuth開始ログ
  def log_oauth_initiation(provider, results)
    log_data = {
      event: "oauth_initiation",
      provider: provider,
      ip_address: request.remote_ip,
      user_agent: sanitize_user_agent(request.user_agent),
      validation_results: results,
      timestamp: Time.current.iso8601
    }

    if results.values.all?
      Rails.logger.info(log_data.to_json)
    else
      Rails.logger.warn(log_data.to_json)
    end
  end

  # OAuth コールバックログ
  def log_oauth_callback(auth_hash, results)
    log_data = {
      event: "oauth_callback",
      provider: auth_hash&.provider,
      user_uid: auth_hash&.uid,
      user_email: sanitize_email(auth_hash&.info&.email),
      validation_results: results,
      timestamp: Time.current.iso8601
    }

    if results.values.all?
      Rails.logger.info(log_data.to_json)
    else
      Rails.logger.error(log_data.to_json)
    end
  end

  # セキュリティイベントログ
  def log_security_event(event_type, details)
    log_data = {
      event: "oauth_security_#{event_type}",
      ip_address: request.remote_ip,
      user_agent: sanitize_user_agent(request.user_agent),
      details: details,
      timestamp: Time.current.iso8601
    }

    Rails.logger.warn(log_data.to_json)
  end

  # User-Agentのサニタイズ
  def sanitize_user_agent(user_agent)
    return "[BLANK]" if user_agent.blank?

    # 長すぎるUser-Agentを制限
    sanitized = user_agent.length > 200 ? user_agent[0..199] + "[TRUNCATED]" : user_agent

    # 潜在的に悪意のある文字列をフィルタリング
    sanitized.gsub(/[<>"\']/, "[FILTERED]")
  end

  # メールアドレスのサニタイズ
  def sanitize_email(email)
    return "[BLANK]" if email.blank?

    # メールアドレスの一部をマスク
    parts = email.split("@")
    return email if parts.length != 2

    username = parts[0]
    domain = parts[1]

    if username.length > 2
      masked_username = "#{username[0]}***#{username[-1]}"
    else
      masked_username = "***"
    end

    "#{masked_username}@#{domain}"
  end
end
