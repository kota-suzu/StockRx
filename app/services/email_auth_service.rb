# frozen_string_literal: true

# 🔐 EmailAuthService - 店舗ログイン用一時パスワードメール認証サービス
# ============================================================================
# CLAUDE.md準拠: Phase 1 メール認証機能のビジネスロジック層
#
# 目的:
#   - 一時パスワード生成とメール送信の統合処理
#   - SecurityComplianceManager統合による企業レベルセキュリティ
#   - TempPasswordモデルとの連携による安全な認証フロー
#
# 設計思想:
#   - セキュリティ・バイ・デザイン原則
#   - 既存サービスクラスとの一貫性確保
#   - メタ認知的エラーハンドリング（早期失敗・段階的回復）
# ============================================================================

class EmailAuthService
  include ActiveSupport::Configurable

  # ============================================================================
  # エラークラス定義（SecurityComplianceManagerパターン踏襲）
  # ============================================================================
  class EmailAuthError < StandardError; end
  class TempPasswordGenerationError < EmailAuthError; end
  class EmailDeliveryError < EmailAuthError; end
  class SecurityViolationError < EmailAuthError; end
  class RateLimitExceededError < SecurityViolationError; end
  class UserIneligibleError < SecurityViolationError; end

  # ============================================================================
  # 設定定数（BatchProcessorパターン踏襲）
  # ============================================================================
  config_accessor :max_attempts_per_hour, default: 3
  config_accessor :max_attempts_per_day, default: 10
  config_accessor :temp_password_expiry, default: 15.minutes
  config_accessor :rate_limit_enabled, default: true
  config_accessor :email_delivery_timeout, default: 30.seconds
  config_accessor :security_monitoring_enabled, default: true

  # Redis キーパターン（レート制限用）
  RATE_LIMIT_KEY_PATTERN = "email_auth_service:rate_limit:%<email>s:%<ip>s"
  HOURLY_ATTEMPTS_KEY_PATTERN = "email_auth_service:hourly:%<email>s"
  DAILY_ATTEMPTS_KEY_PATTERN = "email_auth_service:daily:%<email>s"

  # ============================================================================
  # パブリックインターフェース
  # ============================================================================

  # 設定変更用インターフェース
  def configure
    yield(config) if block_given?
  end

  # 一時パスワード生成とメール送信の統合処理
  def generate_and_send_temp_password(store_user, admin_id: nil, request_metadata: {})
    request_metadata ||= {}

    begin
      validate_rate_limit(store_user.email, request_metadata[:ip_address])
    rescue RateLimitExceededError => e
      return handle_rate_limit_exceeded(e, store_user, request_metadata)
    end

    # Phase 1: バリデーション（早期失敗）
    validate_user_eligibility(store_user)

    begin
      # Phase 2: 一時パスワード生成（TempPasswordモデル統合）
      temp_password, plain_password = generate_temp_password(
        store_user,
        admin_id: admin_id,
        request_metadata: request_metadata
      )

      # Phase 3: メール送信（AdminMailer統合）
      delivery_result = deliver_temp_password_email(store_user, plain_password, temp_password)

      # Phase 4: 成功処理
      handle_successful_generation(store_user, temp_password, admin_id, request_metadata)

      {
        success: true,
        temp_password_id: temp_password.id,
        expires_at: temp_password.expires_at,
        delivery_result: delivery_result
      }

    rescue RateLimitExceededError => e
      handle_rate_limit_exceeded(e, store_user, request_metadata)
    rescue TempPasswordGenerationError => e
      handle_generation_error(e, store_user, admin_id, request_metadata)
    rescue EmailDeliveryError => e
      handle_delivery_error(e, store_user, temp_password, request_metadata)
    rescue => e
      handle_unexpected_error(e, store_user, admin_id, request_metadata)
    end
  end

  # 一時パスワード検証とログイン処理
  def authenticate_with_temp_password(store_user, password, request_metadata: {})
    begin
      # Phase 1: 有効な一時パスワード検索
      temp_password = find_valid_temp_password(store_user)
      return authentication_failed_result("no_valid_temp_password") unless temp_password

      # Phase 2: レート制限チェック（ブルートフォース対策）
      validate_authentication_rate_limit(store_user, request_metadata[:ip_address])

      # Phase 3: パスワード検証
      if temp_password.valid_password?(password)
        # 成功処理
        temp_password.mark_as_used!(
          ip_address: request_metadata[:ip_address],
          user_agent: request_metadata[:user_agent]
        )

        handle_successful_authentication(store_user, temp_password, request_metadata)

        {
          success: true,
          temp_password_id: temp_password.id,
          temp_password: temp_password,  # 🔧 コントローラー用にオブジェクトも返す
          authenticated_at: Time.current
        }
      else
        # 失敗処理
        temp_password.increment_usage_attempts!(ip_address: request_metadata[:ip_address])
        handle_failed_authentication(store_user, temp_password, request_metadata)

        authentication_failed_result("invalid_password")
      end

    rescue SecurityViolationError => e
      handle_security_violation(e, store_user, request_metadata)
    rescue => e
      handle_authentication_error(e, store_user, request_metadata)
    end
  end

  # 期限切れ一時パスワードのクリーンアップ（管理者用）
  def cleanup_expired_passwords
    cleanup_count = TempPassword.cleanup_expired

    log_security_event(
      "temp_passwords_cleanup",
      nil,
      {
        cleaned_count: cleanup_count,
        performed_by: "EmailAuthService",
        performed_at: Time.current
      }
    )

    cleanup_count
  end

  # レート制限チェック（外部公開用）
  def rate_limit_check(email, ip_address)
    return true unless config.rate_limit_enabled

    # 時間別制限チェック
    hourly_key = HOURLY_ATTEMPTS_KEY_PATTERN % { email: email }
    hourly_count = get_rate_limit_count(hourly_key)

    return false if hourly_count >= config.max_attempts_per_hour

    # 日別制限チェック
    daily_key = DAILY_ATTEMPTS_KEY_PATTERN % { email: email }
    daily_count = get_rate_limit_count(daily_key)

    return false if daily_count >= config.max_attempts_per_day

    # IP別制限チェック
    ip_key = RATE_LIMIT_KEY_PATTERN % { email: email, ip: ip_address }
    ip_count = get_rate_limit_count(ip_key)

    return false if ip_count >= config.max_attempts_per_hour

    true
  end

  # 認証試行記録（外部公開用）
  # CLAUDE.md準拠: 適切なカプセル化によるセキュリティ機能提供
  # メタ認知: privateメソッドへの適切なpublicインターフェース
  # 横展開: 他のサービスクラスでも同様のパターン適用
  def record_authentication_attempt(email, ip_address)
    return unless config.rate_limit_enabled

    begin
      increment_rate_limit_counter(email, ip_address)

      log_security_event(
        "authentication_attempt_recorded",
        nil,
        {
          email: email,
          ip_address: ip_address,
          recorded_at: Time.current
        }
      )

      true
    rescue => e
      Rails.logger.error "[EmailAuthService] Failed to record authentication attempt: #{e.message}"
      false
    end
  end

  # ============================================================================
  # プライベートメソッド
  # ============================================================================

  private

  # ============================================
  # 一時パスワード生成関連
  # ============================================

  def generate_temp_password(store_user, admin_id:, request_metadata:)
    temp_password, plain_password = TempPassword.generate_for_user(
      store_user,
      admin_id: admin_id,
      ip_address: request_metadata[:ip_address],
      user_agent: request_metadata[:user_agent]
    )

    log_security_event(
      "temp_password_generated",
      store_user,
      {
        temp_password_id: temp_password.id,
        admin_id: admin_id,
        ip_address: request_metadata[:ip_address],
        expires_at: temp_password.expires_at
      }
    )

    [ temp_password, plain_password ]
  rescue => e
    raise TempPasswordGenerationError, "Failed to generate temp password: #{e.message}"
  end

  # ============================================
  # メール送信関連
  # ============================================

  def deliver_temp_password_email(store_user, plain_password, temp_password)
    # Phase 1: StoreAuthMailer統合完了
    # CLAUDE.md準拠: メール送信と適切なエラーハンドリング
    begin
      Rails.logger.info "📧 [EmailAuthService] Sending temp password email to #{store_user.email}"

      # StoreAuthMailerを使用してメール送信
      mail = StoreAuthMailer.temp_password_notification(store_user, plain_password, temp_password)
      delivery_result = mail.deliver_now

      Rails.logger.info "✅ [EmailAuthService] Email sent successfully via #{ActionMailer::Base.delivery_method}"

      {
        success: true,
        delivery_method: ActionMailer::Base.delivery_method.to_s,
        delivered_at: Time.current,
        message_id: delivery_result.try(:message_id),
        mail_object: delivery_result
      }

    rescue => e
      Rails.logger.error "❌ [EmailAuthService] Email delivery failed: #{e.message}"
      Rails.logger.error e.backtrace.first(3).join("\n")

      raise EmailDeliveryError, "Failed to deliver temp password email: #{e.message}"
    end
  end

  # ============================================
  # バリデーション関連
  # ============================================

  def validate_rate_limit(email, ip_address)
    return unless config.rate_limit_enabled

    # 時間別制限チェック
    hourly_key = HOURLY_ATTEMPTS_KEY_PATTERN % { email: email }
    hourly_count = redis_increment_with_expiry(hourly_key, 1.hour)

    if hourly_count > config.max_attempts_per_hour
      raise RateLimitExceededError.new("Hourly rate limit exceeded for #{email}")
    end

    # 日別制限チェック
    daily_key = DAILY_ATTEMPTS_KEY_PATTERN % { email: email }
    daily_count = redis_increment_with_expiry(daily_key, 1.day)

    if daily_count > config.max_attempts_per_day
      raise RateLimitExceededError.new("Daily rate limit exceeded for #{email}")
    end

    # IP別制限（セキュリティ強化）
    ip_key = RATE_LIMIT_KEY_PATTERN % { email: email, ip: ip_address }
    ip_count = redis_increment_with_expiry(ip_key, 1.hour)

    if ip_count > config.max_attempts_per_hour
      raise RateLimitExceededError.new("IP-based rate limit exceeded for #{ip_address}")
    end
  end

  # レート制限カウンター増加
  def increment_rate_limit_counter(email, ip_address)
    return unless config.rate_limit_enabled

    # 各キーのカウンターを増加（チェックなし）
    hourly_key = HOURLY_ATTEMPTS_KEY_PATTERN % { email: email }
    redis_increment_with_expiry(hourly_key, 1.hour)

    daily_key = DAILY_ATTEMPTS_KEY_PATTERN % { email: email }
    redis_increment_with_expiry(daily_key, 1.day)

    ip_key = RATE_LIMIT_KEY_PATTERN % { email: email, ip: ip_address }
    redis_increment_with_expiry(ip_key, 1.hour)
  end

  def validate_user_eligibility(store_user)
    unless store_user.active?
      raise UserIneligibleError.new("User account is not active")
    end

    if store_user.locked_at.present?
      raise UserIneligibleError.new("User account is locked")
    end

    # パスワード期限切れユーザーは一時パスワード認証を使用可能
    # （既存のパスワードリセット機能の代替として）
  end

  def validate_authentication_rate_limit(store_user, ip_address)
    # TODO: 🟡 Phase 2重要 - Redis統合によるブルートフォース対策
    # 現在は基本チェックのみ実装
    return unless config.rate_limit_enabled

    Rails.logger.info "[EmailAuthService] Authentication rate limit check for #{store_user.email}"
  end

  # ============================================
  # 認証関連
  # ============================================

  def find_valid_temp_password(store_user)
    store_user.temp_passwords
              .valid
              .unused
              .order(created_at: :desc)
              .first
  end

  def authentication_failed_result(reason)
    {
      success: false,
      error: "authentication_failed",
      reason: reason,
      authenticated_at: nil
    }
  end

  # ============================================
  # 成功・失敗処理
  # ============================================

  def handle_successful_generation(store_user, temp_password, admin_id, request_metadata)
    log_security_event(
      "temp_password_email_sent",
      store_user,
      {
        temp_password_id: temp_password.id,
        admin_id: admin_id,
        ip_address: request_metadata[:ip_address],
        user_agent: request_metadata[:user_agent],
        result: "success"
      }
    )
  end

  def handle_successful_authentication(store_user, temp_password, request_metadata)
    log_security_event(
      "temp_password_authentication_success",
      store_user,
      {
        temp_password_id: temp_password.id,
        ip_address: request_metadata[:ip_address],
        user_agent: request_metadata[:user_agent],
        authenticated_at: Time.current
      }
    )
  end

  def handle_failed_authentication(store_user, temp_password, request_metadata)
    log_security_event(
      "temp_password_authentication_failed",
      store_user,
      {
        temp_password_id: temp_password.id,
        usage_attempts: temp_password.usage_attempts,
        ip_address: request_metadata[:ip_address],
        will_be_locked: temp_password.locked?
      }
    )
  end

  # ============================================
  # エラーハンドリング
  # ============================================

  def handle_generation_error(error, store_user, admin_id, request_metadata)
    log_security_event(
      "temp_password_generation_failed",
      store_user,
      {
        error_class: error.class.name,
        error_message: error.message,
        admin_id: admin_id,
        ip_address: request_metadata[:ip_address]
      }
    )

    {
      success: false,
      error: "temp_password_generation_failed",
      details: error.message
    }
  end

  def handle_delivery_error(error, store_user, temp_password, request_metadata)
    # 一時パスワードは生成されたが送信に失敗
    # セキュリティ上、一時パスワードを無効化
    temp_password&.update_column(:active, false)

    log_security_event(
      "temp_password_delivery_failed",
      store_user,
      {
        error_class: error.class.name,
        error_message: error.message,
        temp_password_id: temp_password&.id,
        temp_password_deactivated: true,
        ip_address: request_metadata[:ip_address]
      }
    )

    {
      success: false,
      error: "email_delivery_failed",
      details: "The temporary password could not be sent via email"
    }
  end

  def handle_rate_limit_exceeded(error, store_user, request_metadata)
    Rails.logger.warn "[EmailAuthService] Rate limit exceeded: #{error.message}"

    log_security_event(
      "temp_password_rate_limit_exceeded",
      store_user,
      {
        error_class: error.class.name,
        error_message: error.message,
        ip_address: request_metadata[:ip_address],
        user_agent: request_metadata[:user_agent]
      }
    )

    {
      success: false,
      error: "rate_limit_exceeded",
      details: error.message
    }
  end

  def handle_unexpected_error(error, store_user, admin_id, request_metadata)
    log_security_event(
      "temp_password_service_error",
      store_user,
      {
        error_class: error.class.name,
        error_message: error.message,
        admin_id: admin_id,
        ip_address: request_metadata[:ip_address],
        backtrace: error.backtrace&.first(5)
      }
    )

    {
      success: false,
      error: "service_error",
      details: "An unexpected error occurred"
    }
  end

  def handle_security_violation(error, store_user, request_metadata)
    log_security_event(
      "temp_password_security_violation",
      store_user,
      {
        violation_type: error.class.name,
        error_message: error.message,
        ip_address: request_metadata[:ip_address],
        user_agent: request_metadata[:user_agent]
      }
    )

    {
      success: false,
      error: "security_violation",
      details: error.message
    }
  end

  def handle_authentication_error(error, store_user, request_metadata)
    log_security_event(
      "temp_password_authentication_error",
      store_user,
      {
        error_class: error.class.name,
        error_message: error.message,
        ip_address: request_metadata[:ip_address]
      }
    )

    {
      success: false,
      error: "authentication_error",
      details: "An error occurred during authentication"
    }
  end

  # ============================================
  # ユーティリティメソッド
  # ============================================

  def redis_increment_with_expiry(key, expiry_time)
    # TODO: 🟡 Phase 2重要 - Redis統合実装
    # 暫定実装（メモリベース）
    rate_limit_cache_mutex.synchronize do
      entry = rate_limit_cache[key]

      if entry.nil? || entry[:expires_at] < Time.current
        rate_limit_cache[key] = { count: 1, expires_at: Time.current + expiry_time }
      else
        entry[:count] += 1
      end

      rate_limit_cache[key][:count]
    end
  end

  def get_rate_limit_count(key)
    # TODO: 🟡 Phase 2重要 - Redis統合実装
    # 暫定実装（メモリベース）
    rate_limit_cache_mutex.synchronize do
      entry = rate_limit_cache[key]
      return 0 unless entry

      if entry[:expires_at] < Time.current
        rate_limit_cache[key] = { count: 0, expires_at: Time.current }
        return 0
      end

      entry[:count]
    end
  end

  def rate_limit_cache
    @rate_limit_cache ||= {}
  end

  def rate_limit_cache_mutex
    @rate_limit_cache_mutex ||= Mutex.new
  end

  def log_security_event(event_type, user, metadata = {})
    return unless config.security_monitoring_enabled

    # TODO: 🔴 Phase 1緊急 - SecurityComplianceManager統合
    # 横展開: ComplianceAuditLogの統合パターン適用
    # 暫定実装（構造化ログ）
    Rails.logger.info({
      event: "email_auth_#{event_type}",
      service: "EmailAuthService",
      user_id: user&.id,
      user_email: user&.email,
      timestamp: Time.current.iso8601,
      **metadata
    }.to_json)
  rescue => e
    Rails.logger.error "[EmailAuthService] Security logging failed: #{e.message}"
  end
end

# ============================================
# TODO: Phase 2以降の機能拡張
# ============================================
# 🔴 Phase 1緊急（1週間以内）:
#   - AdminMailer.temp_password_notification実装
#   - SecurityComplianceManager完全統合
#   - Redis統合（レート制限）
#
# 🟡 Phase 2重要（2週間以内）:
#   - ブルートフォース攻撃対策強化
#   - IP地理的位置チェック機能
#   - デバイス指紋認証統合
#
# 🟢 Phase 3推奨（1ヶ月以内）:
#   - マルチファクター認証統合
#   - SMS/プッシュ通知代替手段
#   - 機械学習ベースの不正検出
