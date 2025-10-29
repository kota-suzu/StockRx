# frozen_string_literal: true

# StockRx セキュリティヘッダー設定
# =====================================
# PCI DSS/GDPR準拠のセキュリティヘッダー設定
# - Content Security Policy (CSP)
# - X-Frame-Options
# - X-Content-Type-Options
# - X-XSS-Protection
# - Strict-Transport-Security
# =====================================

Rails.application.configure do
  # セキュリティヘッダーをすべてのレスポンスに追加
  config.force_ssl = Rails.env.production?

  # Content Security Policy (CSP) 設定
  config.content_security_policy do |policy|
    # 基本的なソース指定
    policy.default_src :self

    # スクリプトソース（Bootstrap、jQuery、Importmap対応）
    policy.script_src :self, :unsafe_inline, :unsafe_eval,
                      "https://cdn.jsdelivr.net",
                      "https://unpkg.com",
                      "https://code.jquery.com"

    # スタイルソース（Bootstrap、Font Awesome対応）
    policy.style_src :self, :unsafe_inline,
                     "https://cdn.jsdelivr.net",
                     "https://fonts.googleapis.com",
                     "https://cdnjs.cloudflare.com"

    # フォントソース
    policy.font_src :self,
                    "https://fonts.gstatic.com",
                    "https://cdnjs.cloudflare.com"

    # 画像ソース（data URIとBlob URL対応）
    policy.img_src :self, :data, :blob,
                   "https://cdn.jsdelivr.net"

    # 接続ソース（WebSocket、AJAX対応）
    policy.connect_src :self, :ws, :wss

    # オブジェクト・メディアソース
    policy.object_src :none
    policy.media_src :self

    # フレームソース（iframeなど）
    policy.frame_src :none

    # フォーム送信先
    policy.form_action :self

    # ベースURI
    policy.base_uri :self

    # フレーム祖先（Clickjacking対策）
    policy.frame_ancestors :none

    # アップグレード不安全な要求
    policy.upgrade_insecure_requests true if Rails.env.production?

    # レポートURI（本番環境でのCSP違反レポート）
    if Rails.env.production?
      policy.report_uri "/csp-report"
    end
  end

  # Content Security Policy 違反時のレポート設定
  config.content_security_policy_report_only = Rails.env.development?
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }

  # セキュリティヘッダーのカスタマイズ
  config.session_store :cookie_store,
    key: "_stockrx_session",
    secure: Rails.env.production?,
    httponly: true,
    same_site: :lax,
    expire_after: 30.minutes

  # 追加のセキュリティヘッダー設定
  config.middleware.use Rack::Attack if defined?(Rack::Attack)

  # HTTPSリダイレクト設定（本番環境のみ）
  if Rails.env.production?
    config.ssl_options = {
      redirect: {
        exclude: ->(request) {
          request.path.start_with?("/health") ||
          request.path.start_with?("/status")
        }
      },
      secure_cookies: true,
      hsts: {
        max_age: 31536000, # 1年
        include_subdomains: true,
        preload: true
      }
    }
  end
end

# Rackミドルウェアでセキュリティヘッダーを設定
Rails.application.config.middleware.use(
  Rack::Static,
  urls: [ "/security.txt" ],
  route: "/security.txt",
  root: Rails.root.join("public")
)

# セキュリティヘッダーミドルウェア
class SecurityHeadersMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)

    # セキュリティヘッダーを追加
    headers.merge!(security_headers)

    [ status, headers, response ]
  end

  private

  def security_headers
    {
      # XSSフィルタリング
      "X-XSS-Protection" => "1; mode=block",

      # コンテンツタイプスニッフィング防止
      "X-Content-Type-Options" => "nosniff",

      # フレーム埋め込み防止（Clickjacking対策）
      "X-Frame-Options" => "DENY",

      # リファラー情報制御
      "Referrer-Policy" => "strict-origin-when-cross-origin",

      # 機能ポリシー（カメラ、マイクなどの制限）
      "Permissions-Policy" => [
        "camera=()",
        "microphone=()",
        "geolocation=()",
        "interest-cohort=()"
      ].join(", "),

      # セキュリティ情報
      "X-Permitted-Cross-Domain-Policies" => "none",

      # キャッシュ制御（機密データ）
      "Cache-Control" => "no-store, no-cache, must-revalidate, private",
      "Pragma" => "no-cache",
      "Expires" => "0"
    }
  end
end

# セキュリティヘッダーミドルウェアを追加
Rails.application.config.middleware.use SecurityHeadersMiddleware
