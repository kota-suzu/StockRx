# frozen_string_literal: true

# ============================================
# Application Mailer for StockRx
# ============================================
# 在庫管理システム用メール送信基盤
# 共通設定・セキュリティ・国際化対応

class ApplicationMailer < ActionMailer::Base
  # ============================================
  # 基本設定
  # ============================================
  default from: ENV.fetch("MAILER_FROM", "stockrx-noreply@example.com")
  layout "mailer"

  # ============================================
  # セキュリティ・品質向上
  # ============================================

  # メール送信前の共通処理
  before_action :set_locale
  before_action :validate_email_settings
  before_action :log_email_attempt

  # メール送信後の処理
  after_action :log_email_sent

  private

  # 国際化対応：受信者の言語設定に基づくロケール設定
  def set_locale
    # 受信者が管理者の場合、管理者の設定言語を使用
    if params[:admin]
      I18n.locale = params[:admin].preferred_locale || I18n.default_locale
    else
      I18n.locale = I18n.default_locale
    end
  end

  # メール設定の検証
  def validate_email_settings
    # 本番環境でのメール設定確認
    if Rails.env.production?
      unless ENV["SMTP_USERNAME"].present? && ENV["SMTP_PASSWORD"].present?
        Rails.logger.error "💥 [ApplicationMailer] SMTP credentials not configured for production"
        Rails.logger.error "Available ENV keys: #{ENV.keys.grep(/SMTP|MAIL/).inspect}"
        raise StandardError, "SMTP設定が不完全です。システム管理者にお問い合わせください。"
      end
    end

    Rails.logger.debug "✅ [ApplicationMailer] Email settings validation passed"
  rescue => e
    Rails.logger.error "💥 [ApplicationMailer] Email settings validation failed: #{e.message}"
    raise e
  end

  # メール送信試行をログに記録
  def log_email_attempt
    Rails.logger.info({
      event: "email_attempt",
      mailer: self.class.name,
      action: action_name,
      locale: I18n.locale,
      timestamp: Time.current.iso8601
    }.to_json)
  end

  # メール送信完了をログに記録
  def log_email_sent
    Rails.logger.info({
      event: "email_sent",
      mailer: self.class.name,
      action: action_name,
      to: mail.to&.first,
      subject: mail.subject,
      message_id: mail.message_id,
      timestamp: Time.current.iso8601
    }.to_json)
  rescue => e
    Rails.logger.error "Email logging failed: #{e.message}"
  end

  # TODO: 将来的な機能拡張
  # ============================================
  # 1. 高度なメール機能
  #    - HTMLとテキストの自動生成
  #    - 添付ファイル管理
  #    - メールテンプレート管理
  #
  # 2. 配信最適化
  #    - バウンス処理
  #    - 配信停止管理
  #    - 配信スケジューリング
  #
  # 3. 追跡・分析
  #    - 開封率追跡
  #    - クリック率追跡
  #    - 配信エラー分析
  #
  # 4. セキュリティ強化
  #    - SPF/DKIM/DMARC対応
  #    - 暗号化メール対応
  #    - フィッシング対策

  protected

  # 共通ヘルパーメソッド：管理者用メールの共通設定
  def admin_mail_defaults(admin)
    {
      to: admin.email,
      from: ENV.fetch("MAILER_FROM", "stockrx-noreply@example.com"),
      reply_to: ENV.fetch("MAILER_REPLY_TO", "stockrx-support@example.com")
    }
  end

  # 共通ヘルパーメソッド：緊急通知用メール設定
  def urgent_mail_defaults
    {
      from: ENV.fetch("MAILER_URGENT_FROM", "stockrx-urgent@example.com"),
      importance: "high",
      priority: "urgent"
    }
  end

  # 共通ヘルパーメソッド：システム通知用メール設定
  def system_mail_defaults
    {
      from: ENV.fetch("MAILER_SYSTEM_FROM", "stockrx-system@example.com"),
      "X-Mailer" => "StockRx v#{Rails.application.config.version rescue '1.0'}"
    }
  end
end
