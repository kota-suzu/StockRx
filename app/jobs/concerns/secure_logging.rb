# frozen_string_literal: true

# ============================================
# ActiveJob Secure Logging Module
# ============================================
# 目的:
#   - ActiveJobログでの機密情報漏洩防止
#   - GDPR、個人情報保護法等のコンプライアンス対応
#   - セキュリティ監査要件の満足
#
# 機能:
#   - 機密情報パターンの定義と検出
#   - ジョブクラス別フィルタリングルール管理
#   - パフォーマンス最適化済みパターンマッチング
#
# 使用例:
#   include SecureLogging
#   sanitize_arguments(arguments)
#
module SecureLogging
  extend ActiveSupport::Concern

  # ============================================
  # 機密情報検出パターン定義
  # ============================================

  # キー名による機密情報検出パターン（大文字小文字不問）
  SENSITIVE_PARAM_PATTERNS = [
    # 認証・認可関連
    /password/i, /passwd/i, /secret/i, /token/i, /key/i,
    /credential/i, /auth/i, /api_key/i, /access_token/i,
    /refresh_token/i, /bearer/i, /oauth/i, /jwt/i,

    # 個人情報関連（GDPR/個人情報保護法対応）
    /email/i, /mail/i, /phone/i, /tel/i, /mobile/i,
    /ssn/i, /social_security/i, /credit_card/i, /card_number/i,
    /bank_account/i, /iban/i, /routing/i,

    # システム機密情報
    /database_url/i, /connection_string/i, /private_key/i,
    /certificate/i, /webhook_secret/i, /encryption_key/i,
    /session_key/i, /csrf_token/i,

    # 外部API関連
    /api_secret/i, /client_secret/i, /app_secret/i,
    /api_endpoint/i, /endpoint/i, /api_url/i, /webhook_url/i,
    /merchant_id/i, /payment_key/i, /stripe_/i, /paypal_/i,

    # ビジネス機密情報
    /salary/i, /wage/i, /revenue/i, /profit/i, /cost/i,
    /price_override/i, /discount_code/i, /coupon/i
  ].freeze

  # 値による機密情報検出パターン
  SENSITIVE_VALUE_PATTERNS = [
    # APIキー形式（一般的なパターン）
    /^[a-zA-Z0-9_-]{20,}$/, # 20文字以上の英数字・ハイフン・アンダースコア
    /^[A-Z0-9]{32,}$/i,     # 32文字以上の英数字（大文字）

    # 特定サービスのキー形式
    /^sk_[a-zA-Z0-9_]{20,}$/,           # Stripe Secret Key
    /^pk_[a-zA-Z0-9_]{20,}$/,           # Stripe Publishable Key
    /^xoxb-[a-zA-Z0-9-]{10,}$/,         # Slack Bot Token
    /^ghp_[a-zA-Z0-9]{36}$/,            # GitHub Personal Access Token
    /^gho_[a-zA-Z0-9]{36}$/,            # GitHub OAuth Token

    # Base64エンコード形式
    /^[A-Za-z0-9+\/]{40,}={0,2}$/,      # Base64（40文字以上）

    # JWT形式
    /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/,

    # UUIDv4形式（セッションID等で使用）
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,

    # メールアドレス形式
    /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/,

    # 電話番号形式（国際・国内）
    /^\+?[1-9]\d{7,14}$/,               # 国際電話番号
    /^0\d{9,10}$/,                      # 日本国内電話番号

    # クレジットカード番号形式（Luhnアルゴリズムは後でチェック）
    /^\d{13,19}$/,                      # 13-19桁の数字（基本チェック）

    # 銀行口座番号形式
    /^\d{7,8}$/,                        # 日本の銀行口座番号

    # 暗号化ハッシュ形式
    /^[a-f0-9]{32}$/i,                  # MD5
    /^[a-f0-9]{40}$/i,                  # SHA1
    /^[a-f0-9]{64}$/i                   # SHA256
  ].freeze

  # ============================================
  # ジョブクラス別フィルタリング設定
  # ============================================

  # 各ジョブクラスで特別にフィルタリングすべきパラメータ
  JOB_SPECIFIC_FILTERS = {
    "ExternalApiSyncJob" => {
      sensitive_keys: %w[api_token api_secret client_secret webhook_secret],
      sensitive_paths: [ "options.api_token", "options.credentials", "options.auth" ],
      description: "外部API連携での認証情報保護"
    },
    "ImportInventoriesJob" => {
      sensitive_keys: %w[file_path admin_id user_email],
      sensitive_paths: [ "file_path", "metadata.user_info" ],
      description: "CSVインポートでの個人情報・ファイルパス保護"
    },
    "MonthlyReportJob" => {
      sensitive_keys: %w[email_list recipient_data financial_data],
      sensitive_paths: [ "options.recipients", "options.financial_summary" ],
      description: "月次レポートでの財務情報・連絡先保護"
    },
    "StockAlertJob" => {
      sensitive_keys: %w[notification_tokens push_tokens user_contacts],
      sensitive_paths: [ "options.notification_settings", "options.user_preferences" ],
      description: "在庫アラートでの通知情報保護"
    }
  }.freeze

  # ============================================
  # 設定オプション
  # ============================================

  # フィルタリング動作設定
  FILTERING_OPTIONS = {
    # フィルタリング後の置換文字列
    filtered_replacement: "[FILTERED]",
    filtered_key_replacement: "[FILTERED_KEY]",

    # パフォーマンス制限
    max_depth: 10,                      # 最大ネスト深度
    max_array_length: 1000,            # 配列の最大長さ
    max_string_length: 10_000,         # 文字列の最大長さ

    # セキュリティレベル設定
    strict_mode: Rails.env.production?, # 本番環境では厳格モード
    debug_mode: Rails.env.development?, # 開発環境でのデバッグ情報出力

    # キャッシュ設定（パフォーマンス最適化）
    enable_pattern_cache: true,
    cache_ttl: 1.hour
  }.freeze

  # ============================================
  # ヘルパーメソッド
  # ============================================

  module ClassMethods
    # ジョブクラス固有のフィルタリング設定を取得
    def sensitive_filtering_config
      JOB_SPECIFIC_FILTERS[name] || {}
    end

    # 機密情報パターンのコンパイル済み正規表現を取得（キャッシュ対応）
    def compiled_sensitive_patterns
      @compiled_sensitive_patterns ||= begin
        Rails.cache.fetch("secure_logging:compiled_patterns:#{SecureLogging.cache_key}",
                         expires_in: FILTERING_OPTIONS[:cache_ttl]) do
          {
            param_patterns: SENSITIVE_PARAM_PATTERNS.map(&:freeze),
            value_patterns: SENSITIVE_VALUE_PATTERNS.map(&:freeze)
          }
        end
      end
    end
  end

  # キャッシュキー生成（パターン変更時の無効化対応）
  def self.cache_key
    @cache_key ||= Digest::SHA256.hexdigest(
      "#{SENSITIVE_PARAM_PATTERNS.join}#{SENSITIVE_VALUE_PATTERNS.join}"
    )[0..15]
  end

  # 開発環境でのデバッグヘルパー
  def debug_filtering_result(original, filtered, context = nil)
    return unless FILTERING_OPTIONS[:debug_mode]

    Rails.logger.debug({
      event: "secure_logging_debug",
      context: context || self.class.name,
      original_keys: extract_debug_keys(original),
      filtered_keys: extract_debug_keys(filtered),
      filtering_applied: original != filtered,
      timestamp: Time.current.iso8601
    }.to_json)
  end

  private

  def extract_debug_keys(obj, prefix = "", keys = [])
    case obj
    when Hash
      obj.each { |k, v| extract_debug_keys(v, "#{prefix}#{k}.", keys) }
    when Array
      obj.each_with_index { |v, i| extract_debug_keys(v, "#{prefix}[#{i}].", keys) }
    else
      keys << prefix.chomp(".") if prefix.present?
    end
    keys
  end

  # ============================================
  # 今後の拡張予定機能（TODO）
  # ============================================
  #
  # 1. 動的パターン学習機能
  #    - 新しい機密情報パターンの自動検出
  #    - 機械学習による誤検出率の改善
  #    - 組織固有のパターン学習
  #
  # 2. 監査・コンプライアンス機能
  #    - フィルタリング統計の収集・分析
  #    - コンプライアンスレポート自動生成
  #    - 機密情報アクセスの監査ログ
  #
  # 3. 国際化・多言語対応
  #    - 多言語での機密情報キーワード検出
  #    - 地域別コンプライアンス要件対応
  #    - Unicode文字対応の強化
  #
  # 4. 高度なセキュリティ機能
  #    - 暗号化による可逆フィルタリング
  #    - 権限レベル別表示制御
  #    - セキュリティインシデント検出
  #
  # 5. パフォーマンス最適化
  #    - 並列処理による高速化
  #    - インクリメンタルパターンマッチング
  #    - メモリ使用量の最適化
end
