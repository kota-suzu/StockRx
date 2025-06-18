# frozen_string_literal: true

# 🔐 StoreAuthMailer - 店舗ユーザー認証メール送信クラス
# ============================================================================
# CLAUDE.md準拠: Phase 1 メール認証機能のプレゼンテーション層
# 
# 目的:
#   - 店舗ユーザー向け一時パスワード通知メール送信
#   - ApplicationMailer統合による一貫性確保
#   - セキュリティヘッダー設定とログ統合
#
# 設計思想:
#   - AdminMailerパターン踏襲による統一性
#   - セキュリティ・バイ・デザイン原則（機密情報保護）
#   - レスポンシブデザイン対応のHTMLテンプレート
# ============================================================================

class StoreAuthMailer < ApplicationMailer
  # ApplicationMailerの設定を継承:
  # - セキュリティヘッダー設定
  # - 国際化対応（set_locale）
  # - メール送信ログ（log_email_attempt/log_email_sent）
  # - エラーハンドリング（validate_email_settings）

  # ============================================
  # セキュリティ強化設定
  # ============================================
  before_action :log_sensitive_email_attempt
  after_action :sanitize_temp_password_from_logs

  # ============================================
  # メール送信メソッド
  # ============================================

  # 一時パスワード通知メール送信
  # @param store_user [StoreUser] 対象店舗ユーザー
  # @param plain_password [String] 平文の一時パスワード
  # @param temp_password [TempPassword] 一時パスワードモデル
  # @return [ActionMailer::MessageDelivery] メール配信オブジェクト
  def temp_password_notification(store_user, plain_password, temp_password)
    @store_user = store_user
    @plain_password = plain_password
    @temp_password = temp_password
    @store = store_user.store
    @expires_at = temp_password.expires_at
    @time_until_expiry = temp_password.time_until_expiry
    
    # 店舗専用ログインURL生成
    @login_url = "#{Rails.env.production? ? 'https' : 'http'}://#{ENV.fetch('MAIL_HOST', 'localhost')}:#{ENV.fetch('MAIL_PORT', 3000)}/stores/#{@store.slug}/sign_in"

    # セキュリティメタデータ設定
    @security_metadata = {
      generated_at: temp_password.created_at,
      expires_in_words: "#{@time_until_expiry / 60}分",
      store_name: @store.name,
      user_name: @store_user.name
    }

    mail(
      **store_mail_defaults(store_user),
      subject: I18n.t(
        "store_auth_mailer.temp_password_notification.subject",
        store_name: @store.name
      ),
      # 一時パスワードメール専用の優先度設定
      **urgent_mail_defaults
    )
  end

  # パスワードリセット完了通知（将来拡張用）
  # TODO: 🟡 Phase 2重要 - パスワード変更完了通知実装
  def password_changed_notification(store_user)
    @store_user = store_user
    @store = store_user.store
    @changed_at = Time.current

    mail(
      **store_mail_defaults(store_user),
      subject: I18n.t(
        "store_auth_mailer.password_changed_notification.subject",
        store_name: @store.name
      )
    )
  end

  # セキュリティアラート通知（将来拡張用）
  # TODO: 🟢 Phase 3推奨 - セキュリティ関連通知実装
  def security_alert_notification(store_user, alert_type, details = {})
    @store_user = store_user
    @store = store_user.store
    @alert_type = alert_type
    @details = details
    @alert_time = Time.current

    mail(
      **store_mail_defaults(store_user),
      subject: I18n.t(
        "store_auth_mailer.security_alert_notification.subject",
        alert_type: I18n.t("security_alerts.#{alert_type}.name"),
        store_name: @store.name
      ),
      **urgent_mail_defaults
    )
  end

  private

  # ============================================
  # メール設定メソッド
  # ============================================

  # 店舗ユーザー用メール設定（AdminMailerパターン踏襲）
  def store_mail_defaults(store_user)
    {
      to: store_user.email,
      from: ENV.fetch("MAILER_STORE_FROM", "store-noreply@stockrx.example.com"),
      reply_to: ENV.fetch("MAILER_STORE_REPLY_TO", "store-support@stockrx.example.com"),
      # ApplicationMailerの基本設定継承
      **system_mail_defaults,
      # 店舗メール専用のカスタムヘッダー
      "X-Store-ID" => store_user.store_id.to_s,
      "X-Store-Slug" => store_user.store.slug,
      "X-User-Role" => store_user.role,
      "X-Mailer-Type" => "StoreAuth"
    }
  end

  # 緊急メール用の設定（一時パスワード等）
  def urgent_mail_defaults
    {
      # 高優先度設定
      "X-Priority" => "1",
      "X-MSMail-Priority" => "High",
      "Importance" => "High",
      # セキュリティ関連の追加ヘッダー
      "X-Security-Level" => "High",
      "X-Auto-Response-Suppress" => "All"
    }
  end

  # ============================================
  # セキュリティ強化メソッド
  # ============================================

  # 機密メール送信試行のログ記録
  def log_sensitive_email_attempt
    # 一時パスワード関連のメール送信を特別にログ記録
    if action_name == "temp_password_notification"
      Rails.logger.info({
        event: "sensitive_email_attempt",
        mailer: self.class.name,
        action: action_name,
        to_email_masked: mask_email(params[:store_user]&.email),
        store_id: params[:store_user]&.store_id,
        store_slug: params[:store_user]&.store&.slug,
        temp_password_id: params[:temp_password]&.id,
        security_level: "high",
        timestamp: Time.current.iso8601
      }.to_json)
    end
  end

  # メール送信後の機密情報サニタイズ
  def sanitize_temp_password_from_logs
    # ログから一時パスワードの平文を除去
    if defined?(@plain_password)
      Rails.logger.info({
        event: "temp_password_sanitized",
        action: action_name,
        password_length: @plain_password&.length,
        sanitized_at: Time.current.iso8601
      }.to_json)
      
      # メモリから機密情報を削除
      @plain_password = "[SANITIZED]"
    end
  end

  # メールアドレスマスキング（セキュリティログ用）
  def mask_email(email)
    return "[NO_EMAIL]" unless email.present?
    
    name, domain = email.split('@')
    return "[INVALID_EMAIL]" unless name && domain && name.length > 0
    
    # 最初の文字と最後の文字のみ表示、中間をマスク
    if name.length == 1
      "#{name[0]}***@#{domain}"
    elsif name.length == 2
      "#{name[0]}*@#{domain}"
    else
      "#{name[0]}***#{name[-1]}@#{domain}"
    end
  end

  # ============================================
  # 通知設定統合（将来拡張）
  # ============================================

  # 通知設定チェック（AdminNotificationSettingパターン）
  def notification_enabled?(store_user, notification_type)
    # TODO: 🟡 Phase 2重要 - StoreNotificationSetting統合
    # 優先度: 重要（通知制御機能）
    # 実装内容:
    #   - StoreNotificationSettingモデル作成
    #   - AdminNotificationSettingと同様の機能実装
    #   - 通知頻度制限・有効期間チェック
    # 横展開: AdminNotificationSettingのパターン適用
    # 現在は常に有効として扱う
    
    case notification_type
    when :temp_password
      # 一時パスワード通知は常に有効（セキュリティ要件）
      true
    when :password_changed
      # パスワード変更通知（将来実装）
      true
    when :security_alert
      # セキュリティアラート（将来実装）
      true
    else
      false
    end
  end

  # 通知設定の記録
  def record_notification_sent(store_user, notification_type)
    # TODO: 🟡 Phase 2重要 - 通知履歴記録実装
    Rails.logger.info({
      event: "store_notification_sent",
      notification_type: notification_type,
      store_user_id: store_user.id,
      store_id: store_user.store_id,
      sent_at: Time.current.iso8601
    }.to_json)
  end
end

# ============================================
# TODO: Phase 2以降の機能拡張
# ============================================
# 🔴 Phase 1緊急（1週間以内）:
#   - HTMLテンプレート実装（レスポンシブ対応）
#   - I18n設定（日本語・英語）
#   - EmailAuthService統合テスト
#
# 🟡 Phase 2重要（2週間以内）:
#   - StoreNotificationSetting統合
#   - CSPヘッダー設定
#   - メール配信エラーハンドリング強化
#   - パスワード変更完了通知実装
#
# 🟢 Phase 3推奨（1ヶ月以内）:
#   - セキュリティアラート通知
#   - メール配信統計・分析機能
#   - A/Bテスト対応（テンプレート切り替え）
#   - マルチテナント対応（店舗別カスタマイズ）