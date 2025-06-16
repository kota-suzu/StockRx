# frozen_string_literal: true

# セキュリティヘッダーを設定するConcern
# ============================================
# Phase 5-3: セキュリティ強化
# OWASP推奨のセキュリティヘッダー実装
# CLAUDE.md準拠: セキュリティ最優先
# ============================================
module SecurityHeaders
  extend ActiveSupport::Concern

  included do
    # 全アクションでセキュリティヘッダーを設定
    before_action :set_security_headers
    
    # NonceをビューやJavaScriptで使用可能にする
    helper_method :content_security_policy_nonce if respond_to?(:helper_method)
  end

  private

  # セキュリティヘッダーの設定
  def set_security_headers
    # Content Security Policy (CSP)
    # XSS攻撃を防ぐための強力な防御メカニズム
    set_content_security_policy

    # X-Frame-Options
    # クリックジャッキング攻撃を防ぐ
    response.headers['X-Frame-Options'] = 'DENY'

    # X-Content-Type-Options
    # MIMEタイプスニッフィングを防ぐ
    response.headers['X-Content-Type-Options'] = 'nosniff'

    # X-XSS-Protection (レガシーブラウザ対応)
    # モダンブラウザではCSPが推奨されるが、互換性のため設定
    response.headers['X-XSS-Protection'] = '1; mode=block'

    # Referrer-Policy
    # リファラー情報の漏洩を制御
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'

    # Permissions-Policy (旧Feature-Policy)
    # ブラウザ機能へのアクセスを制限
    set_permissions_policy

    # HTTPS強制（本番環境のみ）
    if Rails.env.production?
      # Strict-Transport-Security (HSTS)
      # HTTPSの使用を強制
      response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains; preload'
    end

    # カスタムヘッダー
    # アプリケーション固有のセキュリティ情報
    response.headers['X-Application-Name'] = 'StockRx'
    response.headers['X-Security-Version'] = '5.3'
  end

  # Content Security Policy の設定
  def set_content_security_policy
    csp_directives = []

    # デフォルトソース
    csp_directives << "default-src 'self'"

    # スクリプトソース
    if Rails.env.development?
      # 開発環境では webpack-dev-server などのために緩和
      csp_directives << "script-src 'self' 'unsafe-inline' 'unsafe-eval' http://localhost:* ws://localhost:*"
    else
      # 本番環境では nonce を使用
      csp_directives << "script-src 'self' 'nonce-#{content_security_policy_nonce}'"
    end

    # スタイルソース
    if Rails.env.development?
      csp_directives << "style-src 'self' 'unsafe-inline'"
    else
      # 本番環境では nonce を使用
      csp_directives << "style-src 'self' 'nonce-#{content_security_policy_nonce}'"
    end

    # 画像ソース
    csp_directives << "img-src 'self' data: https:"

    # フォントソース
    csp_directives << "font-src 'self' data:"

    # 接続先
    csp_directives << "connect-src 'self' #{websocket_urls}"

    # フレーム先
    csp_directives << "frame-src 'none'"

    # オブジェクトソース
    csp_directives << "object-src 'none'"

    # メディアソース
    csp_directives << "media-src 'self'"

    # ワーカーソース
    csp_directives << "worker-src 'self'"

    # フォームアクション
    csp_directives << "form-action 'self'"

    # フレーム祖先
    csp_directives << "frame-ancestors 'none'"

    # ベースURI
    csp_directives << "base-uri 'self'"

    # アップグレード安全でないリクエスト（HTTPSへ）
    csp_directives << "upgrade-insecure-requests" if Rails.env.production?

    # CSP違反レポート
    if csp_report_uri.present?
      csp_directives << "report-uri #{csp_report_uri}"
      csp_directives << "report-to csp-endpoint"
    end

    response.headers['Content-Security-Policy'] = csp_directives.join('; ')
  end

  # Permissions Policy の設定
  def set_permissions_policy
    permissions = []

    # カメラ
    permissions << "camera=()"

    # マイク
    permissions << "microphone=()"

    # 位置情報
    permissions << "geolocation=()"

    # 支払い
    permissions << "payment=()"

    # USB
    permissions << "usb=()"

    # 加速度計
    permissions << "accelerometer=()"

    # ジャイロスコープ
    permissions << "gyroscope=()"

    # 磁力計
    permissions << "magnetometer=()"

    # 全画面
    permissions << "fullscreen=(self)"

    # 自動再生
    permissions << "autoplay=()"

    response.headers['Permissions-Policy'] = permissions.join(', ')
  end

  # WebSocket URLs の取得
  def websocket_urls
    urls = []
    
    if Rails.env.development?
      urls << "ws://localhost:*"
      urls << "wss://localhost:*"
    end

    if defined?(ActionCable) && ActionCable.server.config.url
      urls << ActionCable.server.config.url
    end

    urls.join(' ')
  end

  # CSP レポート URI
  def csp_report_uri
    # TODO: Phase 5-4 - CSP違反レポート収集エンドポイントの実装
    # Rails.application.routes.url_helpers.csp_reports_url
    nil
  end

  # Content Security Policy Nonce の生成
  def content_security_policy_nonce
    @content_security_policy_nonce ||= SecureRandom.base64(16)
  end

  # ============================================
  # ヘルパーメソッド
  # ============================================

  # スクリプトタグにnonceを付与するヘルパー
  def nonce_javascript_tag(&block)
    content_tag(:script, capture(&block), nonce: content_security_policy_nonce)
  end

  # スタイルタグにnonceを付与するヘルパー
  def nonce_style_tag(&block)
    content_tag(:style, capture(&block), nonce: content_security_policy_nonce)
  end
end

# ============================================
# 使用方法:
# ============================================
# 1. ApplicationControllerにinclude
#    class ApplicationController < ActionController::Base
#      include SecurityHeaders
#    end
#
# 2. ビューでnonceを使用
#    <%= javascript_tag nonce: content_security_policy_nonce do %>
#      console.log('This script has a valid nonce');
#    <% end %>
#
# 3. 特定のアクションでCSPを緩和
#    def special_action
#      # 一時的にCSPを緩和
#      response.headers['Content-Security-Policy'] = "default-src *"
#    end
#
# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 CSP違反レポート収集
#    - 専用エンドポイントの実装
#    - 違反パターンの分析
#    - 自動アラート機能
#
# 2. 🟡 動的CSP生成
#    - ページごとの最適化
#    - 外部リソースの動的許可
#    - A/Bテスト対応
#
# 3. 🟢 セキュリティスコアリング
#    - ヘッダー設定の評価
#    - ベストプラクティスチェック
#    - 改善提案の自動生成