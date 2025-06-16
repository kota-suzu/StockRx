# frozen_string_literal: true

# セキュアなCookie設定
# ============================================
# Phase 5-3: セキュリティ強化
# OWASP推奨のCookieセキュリティ設定
# ============================================

Rails.application.config.session_store :cookie_store,
  key: "_stockrx_session",
  secure: Rails.env.production?,       # HTTPS環境でのみCookieを送信
  httponly: true,                      # JavaScriptからのアクセスを防止
  same_site: :strict,                  # CSRF攻撃を防止
  expire_after: 8.hours                # セッション有効期限

# セッションCookieのセキュリティ設定
Rails.application.config.action_dispatch.cookies_same_site_protection = :strict

# 開発環境でのHTTPS強制を無効化（本番環境では有効）
Rails.application.config.force_ssl = Rails.env.production?

# Cookieの署名・暗号化に使用するキー
# credentials.ymlで管理されているsecret_key_baseを使用

# ============================================
# セキュリティ設定の説明
# ============================================
#
# 1. secure: true
#    - HTTPSでのみCookieを送信
#    - 中間者攻撃（MITM）を防止
#
# 2. httponly: true
#    - JavaScriptからCookieへのアクセスを禁止
#    - XSS攻撃によるCookie窃取を防止
#
# 3. same_site: :strict
#    - 同一サイトからのリクエストでのみCookieを送信
#    - CSRF攻撃を防止
#    - 値の選択肢:
#      - :strict  - 最も厳格（推奨）
#      - :lax     - 一部のクロスサイトリクエストを許可
#      - :none    - すべてのクロスサイトリクエストを許可（非推奨）
#
# 4. expire_after: 8.hours
#    - セッションの有効期限を設定
#    - 長時間の放置によるセッションハイジャックを防止

# ============================================
# Cookie属性の追加設定（Rails 7.0+）
# ============================================
if Rails.version >= "7.0"
  Rails.application.config.action_dispatch.cookies_serializer = :json

  # Cookieの暗号化アルゴリズムを最新に保つ
  Rails.application.config.action_dispatch.use_authenticated_cookie_encryption = true

  # 古い署名済みCookieの読み取りを無効化（セキュリティ向上）
  Rails.application.config.action_dispatch.use_cookies_with_metadata = true
end

# ============================================
# 環境別の追加設定
# ============================================

# 開発環境
if Rails.env.development?
  # 開発環境ではHTTPSを使用しないため、secureフラグを無効化
  Rails.application.config.session_store :cookie_store,
    key: "_stockrx_session_dev",
    secure: false,
    httponly: true,
    same_site: :lax,  # 開発環境では少し緩和
    expire_after: 24.hours  # 開発環境では長めに設定
end

# テスト環境
if Rails.env.test?
  Rails.application.config.session_store :cookie_store,
    key: "_stockrx_session_test",
    secure: false,
    httponly: true,
    same_site: :lax,
    expire_after: 1.hour
end

# ============================================
# カスタムCookie設定ヘルパー
# ============================================

# セキュアなCookieオプションを返すヘルパーメソッド
module SecureCookieOptions
  def self.default_options
    {
      httponly: true,
      secure: Rails.env.production?,
      same_site: :strict
    }
  end

  def self.for_remember_token
    default_options.merge(
      expire_after: 2.weeks  # Remember me機能用
    )
  end

  def self.for_temporary_data
    default_options.merge(
      expire_after: 5.minutes  # 一時的なデータ用
    )
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 Cookie暗号化の強化
#    - AES-256-GCMへの移行
#    - 定期的な暗号鍵のローテーション
#    - HSMとの統合
#
# 2. 🟡 Cookieベースの攻撃検知
#    - Cookie改ざんの検出
#    - セッション固定攻撃の防止
#    - Cookieリプレイ攻撃の検出
#
# 3. 🟢 プライバシー対応
#    - GDPR準拠のCookie同意管理
#    - Cookie使用状況の可視化
#    - ユーザーによるCookie管理機能
