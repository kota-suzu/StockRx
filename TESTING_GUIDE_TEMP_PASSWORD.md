# 🧪 一時パスワード認証機能 テストガイド

## 1. 基本動作確認

### ✅ ログイン画面アクセス

**正しいURL（store_slug付き）**:
```
http://localhost:3000/store/sign_in?store_slug=st001
```

**間違ったURL（store_slugなし）**:
```
http://localhost:3000/store/sign_in  ← 一時パスワード機能が使えません
```

### ✅ タブ切り替え確認

1. ブラウザで開発者ツール（F12）を開く
2. Consoleタブを選択
3. 以下のログが表示されることを確認:
   - `Store login page loaded`
   - タブクリック時: `Email auth tab clicked` または `Password tab clicked`

### ✅ 一時パスワード送信テスト

1. 「一時パスワードでログイン」タブをクリック
2. メールアドレスを入力（例: yamada@central.example.com）
3. 「一時パスワードを送信」ボタンをクリック
4. Consoleログを確認:
   ```
   Email auth form found: /stores/st001/auth/email/request
   Form submit prevented
   Email: yamada@central.example.com
   Sending request to: /stores/st001/auth/email/request
   Response status: 200
   Response data: {success: true, ...}
   ```

## 2. メール確認

### MailHog Web UI
```
http://localhost:8025
```

- 送信されたメールが表示される
- 8桁の一時パスワードを確認

## 3. ログイン完了

1. 8桁の一時パスワードを入力
2. 「ログイン」ボタンをクリック
3. 店舗ダッシュボードへリダイレクト

## 4. トラブルシューティング

### 🔧 「店舗が選択されていません」エラー

**原因**: store_slugパラメータが渡されていない

**解決方法**:
1. URLに `?store_slug=st001` を追加
2. または、店舗選択画面（http://localhost:3000/stores）から開始

### 🔧 タブが切り替わらない

**原因**: JavaScriptエラー

**確認方法**:
1. ブラウザコンソールでエラーを確認
2. 以下のエラーがある場合:
   ```
   Tab elements not found: {...}
   ```
   → ページのHTMLが正しく生成されていない

### 🔧 一時パスワードが送信されない

**原因**: Ajax通信エラー

**確認方法**:
1. Networkタブでリクエストを確認
2. Responseタブでエラーメッセージを確認

## 5. コマンドラインテスト

### ルート確認
```bash
docker-compose exec web bundle exec rake store_login:check_routes
```

### 一時パスワード送信テスト
```bash
docker-compose exec web bundle exec rake store_login:test_email_request[yamada@central.example.com]
```

### 基本的な動作テスト
```bash
docker-compose exec web bundle exec rake email_auth:test_basic
```

## 6. デバッグ情報

### Rails ログ確認
```bash
docker-compose logs -f web
```

### JavaScriptログ確認
ブラウザコンソールで以下を実行:
```javascript
// 現在のタブ状態確認
console.log({
  passwordTab: document.getElementById('password-tab'),
  emailAuthTab: document.getElementById('email-auth-tab'),
  currentStore: document.querySelector('input[name="store_slug"]')?.value
});
```

---

最終更新: 2025-06-18