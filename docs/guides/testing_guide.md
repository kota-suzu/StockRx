# 🧪 StockRx テストガイド - 統合版

最終更新: 2025-06-25

## 📋 目次

1. [概要](#概要)
2. [認証機能テスト](#認証機能テスト)
   - [パスワード認証](#パスワード認証)
   - [パスコード認証](#パスコード認証)
3. [開発環境セットアップ](#開発環境セットアップ)
4. [トラブルシューティング](#トラブルシューティング)
5. [セキュリティチェックリスト](#セキュリティチェックリスト)

## 概要

このガイドでは、StockRxアプリケーションの店舗ユーザー認証機能のテスト方法を説明します。

### 認証方式

1. **パスワード認証**: 従来のメールアドレス＋パスワード方式
2. **パスコード認証**: メール送信による6桁パスコード方式（2ステップ認証）

## 開発環境セットアップ

### 1. 環境起動

```bash
# Docker環境の起動
make up

# ログ確認（別ターミナル）
make logs
```

### 2. メール確認環境

MailHog Web UI: http://localhost:8025

開発環境で送信されたすべてのメールはここで確認できます。

### 3. テストユーザー情報

```ruby
# セントラル薬局（st001）
email: yamada@central.example.com
password: SecurePassword123!

# 東北薬局（st002）
email: sato@tohoku.example.com
password: TohokuPass456!

# 関西薬局（st003）
email: tanaka@kansai.example.com
password: KansaiSecure789!
```

## 認証機能テスト

### パスワード認証

#### 1. アクセス

```
http://localhost:3000/store/sign_in?store_slug=st001
```

**重要**: `store_slug` パラメータは必須です。

#### 2. ログイン手順

1. 「パスワードログイン」タブがデフォルトで選択されている
2. メールアドレスとパスワードを入力
3. 「ログイン」ボタンをクリック
4. 成功時は店舗ダッシュボードへリダイレクト

### パスコード認証

#### 1. タブ切り替え

1. 「パスコードログイン」タブをクリック
2. ブラウザコンソール（F12）で以下のログを確認：
   ```
   👆 [Emergency] Passcode tab clicked - DIRECT ACTIVATION
   ✅ [Emergency] Passcode tab activated successfully
   ```

#### 2. パスコード送信

1. **Step 1: メールアドレス入力**
   - メールアドレスを入力（例: `yamada@central.example.com`）
   - 「パスコードを送信」ボタンをクリック

2. **コンソール確認**
   ```javascript
   // 正常な場合のログ
   Response status: 200
   Response data: {success: true, ...}
   ```

3. **自動画面遷移**
   - Step 1（メール入力）→ Step 2（パスコード入力）
   - 成功メッセージ表示
   - パスコード入力フィールドに自動フォーカス

#### 3. メール確認

1. MailHog Web UI (http://localhost:8025) を開く
2. 以下の内容を確認：
   - 件名: 「StockRx - パスコード通知」
   - 本文: 6桁のパスコード
   - 有効期限: 15分

#### 4. パスコード入力

1. **Step 2: パスコード入力**
   - メールで受信した6桁のパスコードを入力
   - 自動で数字以外の文字は除去される
   - 中央揃えの大きな文字で表示

2. **ログイン**
   - 「ログイン」ボタンをクリック
   - 成功時は店舗ダッシュボードへリダイレクト

#### 5. パスコード再送信

Step 2で「メールアドレス変更」ボタンをクリックすると、Step 1に戻ります。

## デバッグツール

### JavaScriptコンソールコマンド

```javascript
// 現在のタブ状態確認
console.log({
  activeTab: document.querySelector('.nav-tabs .active')?.id,
  activePane: document.querySelector('.tab-pane.active')?.id,
  storeSlug: document.querySelector('input[name="store_slug"]')?.value
});

// Step 1/2の表示状態確認（パスコード認証）
console.log({
  step1: document.getElementById('passcode-step1')?.style.display,
  step2: document.getElementById('passcode-step2')?.style.display
});

// 手動でタブを切り替え
document.getElementById('passcode-tab').click();
```

### Railsコンソールコマンド

```ruby
# 最新のパスコード確認
TempPassword.order(created_at: :desc).first

# 特定ユーザーの有効なパスコード確認
user = StoreUser.find_by(email: 'yamada@central.example.com')
user.temp_passwords.valid.unused.last

# パスコード長の確認（6桁であること）
tp = TempPassword.last
puts tp.plain_password  # 生成直後のみ確認可能

# パスコードのステータス確認
tp = TempPassword.last
{
  expired: tp.expired?,
  used: tp.used?,
  locked: tp.locked?,
  valid_for_auth: tp.valid_for_authentication?,
  attempts: tp.usage_attempts,
  expires_at: tp.expires_at
}
```

### テスト用Rakeタスク

```bash
# ルート確認
docker-compose exec web bundle exec rake store_login:check_routes

# メール送信テスト
docker-compose exec web bundle exec rake store_login:test_email_request[yamada@central.example.com]

# 基本動作テスト
docker-compose exec web bundle exec rake email_auth:test_basic
```

## トラブルシューティング

### 問題: 「店舗が選択されていません」エラー

**原因**: URLに `store_slug` パラメータがない

**解決方法**:
```
# 正しいURL（店舗指定あり）
http://localhost:3000/store/sign_in?store_slug=st001

# または店舗選択画面から開始
http://localhost:3000/stores
```

### 問題: タブが切り替わらない

**原因**: JavaScriptエラーまたはBootstrap初期化問題

**確認方法**:
1. ブラウザコンソールでエラーを確認
2. 以下のログが出力されているか確認：
   ```
   🔥 [EMERGENCY FIX] Direct tab repair script starting...
   ✅ [Emergency] Direct tab repair completed
   ```

**解決方法**:
1. ページをリロード（Ctrl+R / Cmd+R）
2. キャッシュクリア（Ctrl+Shift+R / Cmd+Shift+R）
3. それでも動作しない場合は、ブラウザを再起動

### 問題: パスコードが送信されない

**原因**: メールサーバーまたはバックエンドの問題

**確認手順**:

1. **Docker コンテナ確認**
   ```bash
   docker-compose ps
   # web, mailhog コンテナが起動していることを確認
   ```

2. **Railsログ確認**
   ```bash
   docker-compose logs -f web | grep EmailAuthService
   ```

3. **メールアドレス存在確認**
   ```bash
   docker-compose exec web rails console
   Store.find_by(slug: 'st001').store_users.pluck(:email)
   ```

### 問題: パスコードが6桁より多く入力できる

**原因**: フォームのmaxlength属性が効いていない

**確認方法**:
```javascript
// コンソールで確認
document.querySelector('input[name="temp_password"]').maxLength
// => 6 であるべき
```

## セキュリティチェックリスト

### パスコード認証

- [x] パスコード長: 6桁固定
- [x] 有効期限: 15分
- [x] 使用回数: 1回限り
- [x] 失敗回数制限: 5回でロック
- [x] レート制限: 1時間3回、1日10回まで
- [x] HTTPS必須（本番環境）

### パスワード認証

- [x] 最小12文字
- [x] 大文字・小文字・数字・記号を含む
- [x] ログイン失敗ロック: 5回失敗で15分ロック
- [x] セッションタイムアウト: 30分

### 全般

- [x] CSRF保護
- [x] XSS対策
- [x] SQLインジェクション対策
- [x] セキュアクッキー設定
- [x] 監査ログ記録

## 開発時の注意事項

### JavaScript修正

現在、タブ切り替え機能は緊急修正コードで動作しています。将来的には以下の改善が必要です：

1. **外部JavaScriptファイルへの移行**
   - インラインスクリプトをauthentication.jsに統合
   - CSP（Content Security Policy）準拠

2. **Bootstrap統合の改善**
   - Importmapでの適切な読み込み
   - Turbo対応の強化

### テスト自動化

```ruby
# spec/system/store_authentication_spec.rb の作成推奨
RSpec.describe "Store Authentication", type: :system do
  it "allows password login" do
    # ...
  end
  
  it "allows passcode login" do
    # ...
  end
end
```

## 今後の改善計画

### Phase 1（実装済み）
- ✅ 6桁パスコード対応
- ✅ 2ステップ認証フロー
- ✅ タブUI実装

### Phase 2（計画中）
- [ ] パスコード入力時の自動送信（6桁入力完了時）
- [ ] カウントダウンタイマー表示
- [ ] 1桁ずつの入力フィールド
- [ ] 入力時のアニメーション効果

### Phase 3（将来）
- [ ] SMS認証オプション
- [ ] 生体認証（WebAuthn）
- [ ] IPアドレス制限
- [ ] デバイス認証
- [ ] 異常検知アラート

---

## 関連ドキュメント

- [メール認証実装設計](../design/store_login_email_authentication_design.md)
- [マルチストア管理設計](../design/multi_store_management_design.md)
- [セキュリティ監査レポート](../../doc/SECURITY_AUDIT_EMAIL_AUTH_2025-06-18.md)