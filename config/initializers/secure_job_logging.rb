# frozen_string_literal: true

# ============================================
# Secure Job Logging Configuration
# ============================================
# 目的:
#   - ActiveJobログでの機密情報漏洩防止設定
#   - セキュリティポリシーの一元管理
#   - 開発・ステージング・本番環境での設定調整
#
# このファイルはRailsアプリケーション起動時に自動的に読み込まれ、
# セキュリティ設定をグローバルに適用します。
#

Rails.application.configure do
  # ============================================
  # 機密パラメータフィルタリングの拡張設定
  # ============================================

  # HTTPリクエスト用の既存設定に加えて、
  # ActiveJobの引数用機密パラメータを追加
  config.filter_parameters += [
    # ============================================
    # 認証・認可関連パラメータ
    # ============================================
    :api_key, :access_token, :refresh_token, :bearer_token,
    :client_secret, :webhook_secret, :private_key, :secret_key,
    :auth_token, :authorization_token, :oauth_token,
    :jwt_token, :session_secret, :csrf_token,

    # ============================================
    # 外部API連携用パラメータ
    # ============================================
    :stripe_secret_key, :stripe_publishable_key,
    :paypal_client_secret, :paypal_access_token,
    :github_token, :github_secret,
    :slack_bot_token, :slack_webhook_url,
    :aws_access_key_id, :aws_secret_access_key,
    :gcp_service_account_key, :azure_client_secret,

    # ============================================
    # データベース・インフラ関連
    # ============================================
    :database_password, :database_url, :redis_password,
    :connection_string, :encryption_key, :master_key,

    # ============================================
    # ジョブ特有の機密情報
    # ============================================
    :file_content, :csv_data, :import_data, :export_data,
    :notification_tokens, :push_tokens, :device_tokens,
    :user_credentials, :admin_credentials,

    # ============================================
    # ビジネス機密情報
    # ============================================
    :financial_data, :revenue_data, :cost_data,
    :salary_info, :wage_data, :profit_margin,
    :discount_codes, :coupon_codes, :pricing_info,

    # ============================================
    # 個人情報（GDPR・個人情報保護法対応）
    # ============================================
    :personal_number, :social_security_number, :tax_id,
    :credit_card_number, :bank_account_number, :iban,
    :phone_number, :mobile_number, :home_address,
    :birth_date, :passport_number, :driver_license,

    # ============================================
    # システム・運用関連
    # ============================================
    :backup_encryption_key, :ssl_private_key,
    :monitoring_api_key, :logging_api_key,
    :deployment_key, :ci_cd_token
  ]

  # ============================================
  # 環境別セキュリティ設定
  # ============================================

  if Rails.env.production?
    # 本番環境：最高レベルのセキュリティ
    config.secure_job_logging = {
      enabled: true,
      strict_mode: true,          # 厳格なフィルタリング
      debug_mode: false,          # デバッグ情報出力なし
      performance_monitoring: true, # パフォーマンス監視有効
      audit_logging: true,        # 監査ログ有効
      compliance_mode: true       # コンプライアンスモード有効
    }

  elsif Rails.env.staging?
    # ステージング環境：本番に近い設定でテスト
    config.secure_job_logging = {
      enabled: true,
      strict_mode: true,
      debug_mode: false,
      performance_monitoring: true,
      audit_logging: true,
      compliance_mode: true
    }

  elsif Rails.env.development?
    # 開発環境：デバッグ性を重視
    config.secure_job_logging = {
      enabled: true,
      strict_mode: false,         # やや緩いフィルタリング
      debug_mode: true,           # デバッグ情報出力
      performance_monitoring: true,
      audit_logging: false,       # 監査ログは無効
      compliance_mode: false      # 開発効率を優先
    }

  else
    # テスト環境：テスト実行に最適化
    config.secure_job_logging = {
      enabled: true,
      strict_mode: false,
      debug_mode: false,          # テスト実行速度を重視
      performance_monitoring: false,
      audit_logging: false,
      compliance_mode: false
    }
  end

  # ============================================
  # カスタマイズ可能な設定項目
  # ============================================

  # 環境変数による設定オーバーライド対応
  # 例: SECURE_JOB_LOGGING_ENABLED=false rails server
  if ENV["SECURE_JOB_LOGGING_ENABLED"].present?
    config.secure_job_logging[:enabled] = ActiveModel::Type::Boolean.new.cast(ENV["SECURE_JOB_LOGGING_ENABLED"])
  end

  if ENV["SECURE_JOB_LOGGING_STRICT_MODE"].present?
    config.secure_job_logging[:strict_mode] = ActiveModel::Type::Boolean.new.cast(ENV["SECURE_JOB_LOGGING_STRICT_MODE"])
  end

  if ENV["SECURE_JOB_LOGGING_DEBUG"].present?
    config.secure_job_logging[:debug_mode] = ActiveModel::Type::Boolean.new.cast(ENV["SECURE_JOB_LOGGING_DEBUG"])
  end

  # ============================================
  # パフォーマンス設定
  # ============================================

  config.secure_job_logging_performance = {
    # サニタイズ処理の制限値
    max_argument_depth: ENV.fetch("SECURE_JOB_MAX_DEPTH", 15).to_i,
    max_array_length: ENV.fetch("SECURE_JOB_MAX_ARRAY_LENGTH", 5000).to_i,
    max_string_length: ENV.fetch("SECURE_JOB_MAX_STRING_LENGTH", 50_000).to_i,

    # パフォーマンス監視しきい値
    slow_sanitization_threshold: ENV.fetch("SECURE_JOB_SLOW_THRESHOLD", 0.1).to_f, # 100ms
    memory_warning_threshold: ENV.fetch("SECURE_JOB_MEMORY_THRESHOLD", 50).to_i,   # 50MB

    # キャッシュ設定
    pattern_cache_ttl: ENV.fetch("SECURE_JOB_CACHE_TTL", 1.hour.to_i).to_i,
    enable_pattern_cache: ENV.fetch("SECURE_JOB_CACHE_ENABLED", "true") == "true"
  }

  # ============================================
  # コンプライアンス・監査設定
  # ============================================

  if config.secure_job_logging[:compliance_mode]
    config.secure_job_compliance = {
      # 監査ログの詳細レベル
      audit_level: ENV.fetch("SECURE_JOB_AUDIT_LEVEL", "standard"), # minimal, standard, detailed

      # コンプライアンス要件
      gdpr_compliance: true,        # GDPR対応
      hipaa_compliance: false,      # HIPAA対応（医療情報がある場合）
      pci_compliance: false,        # PCI DSS対応（決済情報がある場合）
      sox_compliance: false,        # SOX法対応（上場企業の場合）

      # データ保護レベル
      data_classification: {
        public: :no_filtering,        # 公開情報
        internal: :basic_filtering,   # 内部情報
        confidential: :standard_filtering,  # 機密情報
        restricted: :strict_filtering # 極秘情報
      },

      # 保持期間設定
      audit_log_retention: ENV.fetch("SECURE_JOB_AUDIT_RETENTION", 90.days.to_i).to_i,
      security_log_retention: ENV.fetch("SECURE_JOB_SECURITY_RETENTION", 1.year.to_i).to_i
    }
  end

  # ============================================
  # アラート・通知設定
  # ============================================

  config.secure_job_alerts = {
    # セキュリティインシデント検出
    enable_security_alerts: Rails.env.production?,

    # アラート閾値
    high_risk_pattern_count: ENV.fetch("SECURE_JOB_HIGH_RISK_THRESHOLD", 10).to_i,
    suspicious_activity_threshold: ENV.fetch("SECURE_JOB_SUSPICIOUS_THRESHOLD", 100).to_i,

    # 通知先設定（環境変数で設定）
    alert_email: ENV["SECURE_JOB_ALERT_EMAIL"],
    slack_webhook: ENV["SECURE_JOB_SLACK_WEBHOOK"],
    teams_webhook: ENV["SECURE_JOB_TEAMS_WEBHOOK"],

    # 通知条件
    notify_on_sanitization_failure: true,
    notify_on_performance_degradation: Rails.env.production?,
    notify_on_suspicious_patterns: Rails.env.production?
  }
end

# ============================================
# ライブラリのオートロード設定（Rails 8.0対応）
# ============================================

# TODO: Rails 8.0互換性修正完了（優先度：完了済み）
# Rails 8.0では autoload_paths の変更は初期化後に凍結されるため、
# application.rb の config.autoload_lib(ignore: %w[assets tasks]) 設定を活用
# この設定により lib/ ディレクトリは自動的にオートロード対象になる
#
# Before: Rails.application.config.autoload_paths << Rails.root.join("lib")
# After:  application.rb の autoload_lib 設定に統合済み
# 理由:   Rails 8.0の設計思想に従い、初期化時の設定を集中管理

# 起動時の初期化確認
Rails.application.config.after_initialize do
  if Rails.application.config.secure_job_logging&.dig(:enabled)
    Rails.logger.info "[SecureJobLogging] Secure job logging initialized successfully"

    # 設定値の検証
    if defined?(SecureLogging) && defined?(SecureArgumentSanitizer)
      Rails.logger.info "[SecureJobLogging] Security modules loaded successfully"
    else
      Rails.logger.warn "[SecureJobLogging] Security modules not found - check autoload configuration"
    end

    # 開発環境での設定概要表示
    if Rails.env.development?
      Rails.logger.info "[SecureJobLogging] Configuration: #{Rails.application.config.secure_job_logging}"
    end
  else
    Rails.logger.warn "[SecureJobLogging] Secure job logging is disabled"
  end
end

# ============================================
# 今後の拡張予定（TODO）
# ============================================
#
# 1. 動的設定更新機能
#    - 運用中の設定変更対応
#    - A/Bテストによる最適化
#    - 機械学習による自動調整
#
# 2. 高度な分析機能
#    - 機密情報検出パターンの統計分析
#    - セキュリティリスクスコアの算出
#    - 異常検出アルゴリズムの導入
#
# 3. 国際化・多地域対応
#    - 地域別コンプライアンス要件対応
#    - 多言語での機密情報検出
#    - タイムゾーン考慮の監査ログ
#
# 4. 統合・外部連携
#    - SIEM システムとの連携
#    - セキュリティ監視ツール連携
#    - コンプライアンス報告の自動化
#
# 5. パフォーマンス最適化
#    - 並列処理による高速化
#    - インクリメンタル学習の導入
#    - リソース使用量の最適化
