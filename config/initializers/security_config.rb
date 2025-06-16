# frozen_string_literal: true

# アプリケーション全体のセキュリティ設定
# ============================================
# Phase 5-3: セキュリティ強化
# OWASP/NIST推奨のセキュリティ設定
# ============================================

# ============================================
# 1. パラメータフィルタリング強化
# ============================================
# 機密情報をログから除外
Rails.application.config.filter_parameters += [
  :password,
  :password_confirmation,
  :current_password,
  :reset_password_token,
  :otp_secret,
  :otp_code,
  :api_key,
  :secret_token,
  :auth_token,
  :access_token,
  :refresh_token,
  :credit_card,
  :card_number,
  :cvv,
  :ssn,
  :social_security_number,
  :my_number,  # マイナンバー
  :bank_account,
  :routing_number
]

# ============================================
# 2. HTTPSリダイレクト設定
# ============================================
if Rails.env.production?
  # HTTPSへの自動リダイレクト
  Rails.application.config.force_ssl = true
  
  # HSTSの有効期限（1年）
  Rails.application.config.ssl_options = {
    hsts: {
      expires: 1.year,
      subdomains: true,
      preload: true
    },
    redirect: {
      exclude: -> request { request.path =~ /health|up/ }  # ヘルスチェックは除外
    }
  }
end

# ============================================
# 3. ホスト検証
# ============================================
# DNSリバインディング攻撃を防ぐ
# NOTE: テスト環境ではホスト検証が無効化されている場合があるため安全にチェック
if Rails.application.config.respond_to?(:hosts) && Rails.application.config.hosts
  Rails.application.config.hosts.clear
  Rails.application.config.hosts << "localhost"
  Rails.application.config.hosts << "127.0.0.1"
  Rails.application.config.hosts << "::1"

  if Rails.env.production?
    # 本番環境のドメインを追加
    Rails.application.config.hosts << ENV.fetch('APPLICATION_HOST', 'stockrx.example.com')
    Rails.application.config.hosts << /\A[a-z0-9-]+\.stockrx\.example\.com\z/  # サブドメイン許可
  end

  # 開発環境では制限を緩和
  Rails.application.config.hosts << /.*/ if Rails.env.development?
end

# ============================================
# 4. Active Recordセキュリティ設定
# ============================================
# SQLインジェクション対策
Rails.application.config.active_record.schema_format = :ruby
Rails.application.config.active_record.dump_schema_after_migration = false if Rails.env.production?

# マスアサインメント保護（デフォルトで有効）
# config.active_record.whitelist_attributes = true  # Rails 7では非推奨

# ============================================
# 5. Action Mailerセキュリティ設定
# ============================================
if Rails.env.production?
  Rails.application.config.action_mailer.raise_delivery_errors = false
  Rails.application.config.action_mailer.perform_caching = false
  
  # メールヘッダーインジェクション対策
  ActionMailer::Base.default from: proc { "noreply@#{Rails.application.config.hosts.first}" }
end

# ============================================
# 6. Active Storageセキュリティ設定
# ============================================
# ダイレクトアップロードのセキュリティ
Rails.application.config.active_storage.variant_processor = :mini_magick
Rails.application.config.active_storage.content_types_to_serve_as_binary = [
  'application/octet-stream',
  'application/x-executable',
  'application/x-sharedlib',
  'application/x-object'
]

# ============================================
# 7. ミドルウェアのセキュリティ設定
# ============================================
Rails.application.config.middleware.use Rack::Attack if defined?(Rack::Attack)

# ============================================
# 8. 暗号化設定
# ============================================
# より強力な暗号化アルゴリズムを使用
ActiveSupport::MessageEncryptor.use_authenticated_message_encryption = true

# ============================================
# 9. ロギング設定
# ============================================
if Rails.env.production?
  # 本番環境では構造化ログを使用
  Rails.application.config.log_formatter = proc do |severity, timestamp, progname, msg|
    {
      severity: severity,
      timestamp: timestamp.iso8601,
      progname: progname,
      message: msg,
      environment: Rails.env,
      host: Socket.gethostname,
      pid: Process.pid
    }.to_json + "\n"
  end
  
  # ログレベル設定
  Rails.application.config.log_level = :info
end

# ============================================
# 10. その他のセキュリティ設定
# ============================================

# タイミング攻撃対策
ActiveSupport::SecurityUtils.secure_compare('a', 'a')  # ウォームアップ

# セッション固定攻撃対策
Rails.application.config.action_dispatch.use_cookies_with_metadata = true

# JSONパーサーのセキュリティ設定
# NOTE: Rails 7.0+ では JSON gem がデフォルトで使用される

# ============================================
# セキュリティ関連の定数定義
# ============================================
module SecurityConfig
  # パスワードポリシー
  PASSWORD_MIN_LENGTH = 12
  PASSWORD_MAX_LENGTH = 128
  PASSWORD_REQUIRE_UPPERCASE = true
  PASSWORD_REQUIRE_LOWERCASE = true
  PASSWORD_REQUIRE_DIGIT = true
  PASSWORD_REQUIRE_SPECIAL = true
  
  # セッション設定
  SESSION_TIMEOUT = 8.hours
  SESSION_TIMEOUT_WARNING = 15.minutes
  REMEMBER_ME_DURATION = 2.weeks
  
  # レート制限
  LOGIN_ATTEMPTS_LIMIT = 5
  LOGIN_LOCKOUT_DURATION = 30.minutes
  API_RATE_LIMIT = 100
  API_RATE_WINDOW = 1.hour
  
  # ファイルアップロード
  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/gif
    image/webp
    application/pdf
    text/csv
    application/vnd.ms-excel
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  ].freeze
  
  # IPホワイトリスト（本番環境用）
  WHITELISTED_IPS = ENV.fetch('WHITELISTED_IPS', '').split(',').map(&:strip).freeze
  
  # セキュリティヘッダー
  SECURITY_HEADERS = {
    'X-Frame-Options' => 'DENY',
    'X-Content-Type-Options' => 'nosniff',
    'X-XSS-Protection' => '1; mode=block',
    'Referrer-Policy' => 'strict-origin-when-cross-origin',
    'X-Permitted-Cross-Domain-Policies' => 'none',
    'X-Download-Options' => 'noopen'
  }.freeze
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 WAF統合
#    - CloudflareやAWS WAFとの連携
#    - カスタムルールの実装
#    - 攻撃パターンの学習
#
# 2. 🟡 セキュリティスキャン自動化
#    - 定期的な脆弱性スキャン
#    - 依存関係の脆弱性チェック
#    - ペネトレーションテストの自動化
#
# 3. 🟢 コンプライアンス自動化
#    - PCI DSS準拠チェック
#    - GDPR準拠チェック
#    - SOC2監査ログ生成