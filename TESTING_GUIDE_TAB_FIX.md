# 🔧 Bootstrap タブ機能修正確認ガイド

## 修正内容

### 問題
- 「一時パスワードでログイン」タブがクリックできない
- Bootstrap JavaScriptが正しく初期化されていない

### 解決策実装
1. **Turboイベント対応**: `turbo:load`イベントでBootstrap初期化
2. **Bootstrap可用性チェック**: 非同期読み込み対応
3. **手動フォールバック**: Bootstrap失敗時の代替機能
4. **エラーハンドリング**: 各段階でのエラー処理

## テスト手順

### 1. サーバー再起動
```bash
# Dockerコンテナを再起動
docker-compose restart web
```

### 2. ブラウザアクセス
```
http://localhost:3000/store/sign_in?store_slug=st001
```

### 3. コンソール確認
ブラウザの開発者ツール（F12）を開き、Consoleタブで以下を確認：

#### 成功パターン
```
Store login page loaded (turbo:load)
🔧 Checking Bootstrap availability...
✅ Bootstrap is available
🔧 Initializing 2 Bootstrap tabs...
✅ Tab 1 initialized: password-tab
✅ Tab 2 initialized: email-auth-tab
```

#### フォールバックパターン（Bootstrapが遅延）
```
Store login page loaded (turbo:load)
🔧 Checking Bootstrap availability...
⚠️ Bootstrap not yet available, retrying...
✅ Bootstrap is available
🔧 Initializing 2 Bootstrap tabs...
```

#### 手動フォールバック（Bootstrap失敗）
```
❌ Failed to initialize tab 1: [error message]
Manual tab switch: email-auth-tab
```

### 4. 動作確認

1. **タブクリック**: 「一時パスワードでログイン」をクリック
2. **表示切替**: パスワード入力フォーム → メール入力フォームに切り替わることを確認
3. **セキュリティ情報**: 下部のセキュリティ情報が切り替わることを確認

### 5. 一時パスワード送信テスト

1. メールアドレス入力: `yamada@central.example.com`
2. 「一時パスワードを送信」ボタンクリック
3. コンソールログ確認:
   ```
   Email auth form found: /stores/st001/auth/email/request
   Form submit prevented
   Email: yamada@central.example.com
   Sending request to: /stores/st001/auth/email/request
   Response status: 200
   Response data: {success: true, ...}
   ```

## デバッグコマンド

### JavaScript状態確認
ブラウザコンソールで実行：
```javascript
// Bootstrap状態確認
console.log('Bootstrap available:', typeof bootstrap !== 'undefined');

// タブ要素確認
console.log({
  tabs: document.querySelectorAll('#loginTabs a[data-bs-toggle="tab"]').length,
  passwordTab: document.getElementById('password-tab'),
  emailAuthTab: document.getElementById('email-auth-tab')
});

// 手動タブ切り替えテスト
document.getElementById('email-auth-tab').click();
```

### ルート確認
```bash
docker-compose exec web bundle exec rake store_login:check_routes
```

## トラブルシューティング

### タブが切り替わらない場合

1. **キャッシュクリア**
   - Ctrl+Shift+R（Windows/Linux）
   - Cmd+Shift+R（Mac）

2. **Bootstrap CDN確認**
   - ネットワークタブでbootstrap.bundle.min.jsが読み込まれているか確認
   - Status: 200 OKであることを確認

3. **Turboキャッシュ無効化テスト**
   ```
   http://localhost:3000/store/sign_in?store_slug=st001&turbo=false
   ```

### 修正が反映されない場合

```bash
# アセットのプリコンパイル
docker-compose exec web bundle exec rails assets:precompile

# サーバー再起動
docker-compose restart web
```

---

修正完了: 2025-06-18