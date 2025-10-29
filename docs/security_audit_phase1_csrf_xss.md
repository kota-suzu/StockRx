# セキュリティ監査レポート - Phase 1: CSRF・XSS対策の完全性検証

## 監査実施日: 2025-06-25

## 監査概要
StockRxシステムのCSRF（Cross-Site Request Forgery）とXSS（Cross-Site Scripting）対策の実装状況を検証しました。

## 監査結果サマリー

### ✅ CSRF対策 - 良好
- **ApplicationController**: デフォルトでCSRF保護が有効
- **ActionController::InvalidAuthenticityToken** の適切なハンドリング実装
- APIコントローラーでは適切にスキップ（APIキー認証使用）

### ⚠️ XSS対策 - 改善の余地あり
- **Rails 8のデフォルトHTMLエスケープ**: 有効
- **html_safe使用箇所**: 12箇所検出（要精査）
- **Content Security Policy**: 基本実装済み、詳細設定が必要

## 詳細分析

### 1. CSRF保護の実装状況

#### ✅ 良好な実装
```ruby
# ApplicationController
class ApplicationController < ActionController::Base
  # デフォルトでprotect_from_forgeryが有効
  
  # CSRF エラーハンドリング
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_csrf_error
```

#### ✅ 適切なスキップ実装
```ruby
# APIコントローラー
class Api::ApiController < ActionController::API
  # APIではCSRF保護をスキップ（APIキー認証使用）
  skip_before_action :verify_authenticity_token
```

```ruby
# CSPレポートコントローラー
class CspReportsController < ApplicationController
  # ブラウザ直接送信のため適切にスキップ
  skip_before_action :verify_authenticity_token
```

### 2. XSS対策の実装状況

#### ⚠️ html_safe使用箇所の精査が必要

**検出された使用箇所:**
1. **flash_messages.html.erb** (line 38)
   ```erb
   <%= msg.html_safe if msg.respond_to?(:html_safe) %>
   ```
   - リスク: フラッシュメッセージにHTMLが含まれる場合のXSS
   - 推奨: sanitizeヘルパーの使用

2. **Kaminariページネーション** (複数ファイル)
   ```erb
   <%= link_to_unless current_page.first?, t('views.pagination.first').html_safe, ... %>
   ```
   - リスク: 低（i18n文字列のため）
   - 推奨: 必要性の再評価

#### ✅ Rails 8のデフォルトエスケープ
```
[Notice] Escaping HTML by default
```
- Rails 8では全ての出力がデフォルトでエスケープされる
- html_safeを明示的に使用しない限り安全

### 3. Content Security Policy (CSP)

#### 現在の実装（SecurityHeaders concern）
```ruby
def set_security_headers
  response.headers['X-Frame-Options'] = 'DENY'
  response.headers['X-Content-Type-Options'] = 'nosniff'
  response.headers['X-XSS-Protection'] = '1; mode=block'
  # CSPの基本設定
```

#### ⚠️ 改善が必要な点
1. **script-src**: 'unsafe-inline' の使用（XSSリスク）
2. **style-src**: 'unsafe-inline' の使用
3. **report-uri**: CSP違反レポートの送信先設定

### 4. セキュリティヘッダーの統一性

#### ✅ 良好な点
- SecurityHeaders concernで統一管理
- 全コントローラーで適用

#### ⚠️ 不足している点
- **Referrer-Policy**: 未設定
- **Permissions-Policy**: 未設定
- **Strict-Transport-Security**: HTTPS環境でのみ有効

## 推奨アクションプラン

### 🔴 緊急（48時間以内）

#### 1. html_safe使用箇所の安全性確認
```ruby
# 修正例: flash_messages.html.erb
<%= sanitize(msg, tags: %w[strong em a], attributes: %w[href class]) %>
```

#### 2. CSP unsafe-inline の段階的削除計画
```ruby
# Phase 1: nonce-based approach
content_security_policy do |policy|
  policy.script_src :self, :nonce
  policy.style_src :self, :nonce
end
```

### 🟡 重要（1週間以内）

#### 1. セキュリティヘッダーの完全実装
```ruby
def set_security_headers
  # 既存のヘッダー
  response.headers['X-Frame-Options'] = 'DENY'
  response.headers['X-Content-Type-Options'] = 'nosniff'
  response.headers['X-XSS-Protection'] = '1; mode=block'
  
  # 追加すべきヘッダー
  response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
  response.headers['Permissions-Policy'] = 'camera=(), microphone=(), geolocation=()'
  
  # HTTPS環境でのみ
  if request.ssl?
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
  end
end
```

#### 2. CSP違反モニタリングの強化
- CspReportsControllerの分析機能追加
- 定期的なレポート生成
- 異常パターンの自動検出

### 🟢 推奨（1ヶ月以内）

#### 1. インラインスクリプト/スタイルの完全削除
- 全てのインラインJavaScriptを外部ファイルへ
- style属性の使用を最小限に
- CSPからunsafe-inlineを完全削除

#### 2. Subresource Integrity (SRI) の実装
```erb
<%= javascript_include_tag 'application', 
    integrity: true, 
    crossorigin: 'anonymous' %>
```

#### 3. 自動セキュリティテストの追加
```ruby
# spec/security/xss_protection_spec.rb
RSpec.describe "XSS Protection" do
  it "escapes user input in all views" do
    # 自動XSSテスト実装
  end
end
```

## セキュリティベストプラクティス

### 入力検証
1. Strong Parametersの徹底使用
2. 入力値のホワイトリスト検証
3. SQLインジェクション対策（次フェーズ）

### 出力エンコーディング
1. デフォルトエスケープの活用
2. コンテキストに応じたエンコーディング
3. JSONレスポンスの適切なエスケープ

### セッション管理
1. secure, httponly cookieフラグ
2. SameSite cookie属性
3. セッションタイムアウト

## 結論

CSRF対策は適切に実装されていますが、XSS対策には改善の余地があります。特に：

1. **html_safe使用箇所の見直し**が最優先
2. **CSPのunsafe-inline削除**が中期目標
3. **セキュリティヘッダーの完全実装**で防御層を追加

継続的なセキュリティテストと監査により、より安全なシステムを維持できます。