# 🔐 6桁パスコード認証機能 テストガイド

## 実装内容

### Phase 1: 6桁パスコード対応 ✅
- 8桁 → 6桁変更（業界標準）
- メールテンプレート更新
- UI入力フィールド調整

### Phase 2: パスコード専用認証フロー ✅
- タブUI削除（シンプル化）
- パスワード認証UI非表示
- 2ステップフロー実装

## テスト手順

### 1. アクセス確認

```
http://localhost:3000/store/sign_in?store_slug=st001
```

**重要**: `?store_slug=st001` パラメータが必須

### 2. パスコード送信テスト

1. **メールアドレス入力**
   - 例: `yamada@central.example.com`
   - 「パスコードを送信」ボタンクリック

2. **コンソール確認（F12）**
   ```
   🔐 Passcode authentication page loaded
   📧 Requesting passcode...
   Response status: 200
   Response data: {success: true, ...}
   ```

3. **画面遷移確認**
   - Step 1（メール入力）→ Step 2（パスコード入力）
   - 成功メッセージ表示
   - パスコード入力フィールドに自動フォーカス

### 3. メール確認

```
http://localhost:8025
```

MailHog Web UIで以下を確認：
- 件名: 「StockRx - パスコード通知」
- 本文: 6桁のパスコード表示

### 4. ログイン完了

1. **6桁パスコード入力**
   - 自動で数字以外の文字を除去
   - 中央揃えで見やすい表示

2. **ログインボタンクリック**
   - 店舗ダッシュボードへリダイレクト

### 5. 再送信機能

1. 「パスコードを再送信」リンククリック
2. 確認ダイアログ表示
3. Step 1に戻る（メールアドレス保持）

## デバッグコマンド

### JavaScriptコンソール

```javascript
// 現在の状態確認
console.log({
  step1: document.getElementById('email-auth-step1').style.display,
  step2: document.getElementById('email-auth-step2').style.display,
  storeSlug: document.querySelector('input[name="store_slug"]')?.value
});

// 手動でStep 2表示
document.getElementById('email-auth-step1').style.display = 'none';
document.getElementById('email-auth-step2').style.display = 'block';
```

### Railsコンソール

```ruby
# 最新のパスコード確認
TempPassword.order(created_at: :desc).first

# パスコード長確認（6桁になっているか）
tp = TempPassword.last
tp.plain_password = TempPassword.generate_secure_password
puts tp.plain_password.length  # => 6
```

## トラブルシューティング

### 問題: 「店舗が選択されていません」

**解決方法**:
```
# 正しいURL
http://localhost:3000/store/sign_in?store_slug=st001

# または店舗選択から開始
http://localhost:3000/stores
```

### 問題: パスコードが送信されない

**確認事項**:
1. Docker コンテナ起動確認
   ```bash
   docker-compose ps
   ```

2. MailHog起動確認
   ```bash
   docker-compose logs mailhog
   ```

3. メールアドレス存在確認
   ```bash
   docker-compose exec web rails console
   Store.find_by(slug: 'st001').store_users.pluck(:email)
   ```

### 問題: 6桁以上入力できる

**対処法**:
- フォームの `maxlength="6"` 属性確認
- JavaScript自動フォーマット機能確認

## セキュリティチェックリスト

- [ ] パスコード有効期限: 15分
- [ ] 使用回数: 1回限り
- [ ] 失敗回数: 5回でロック
- [ ] パスコード長: 6桁固定
- [ ] HTTPS必須（本番環境）

## Phase 3 以降の改善案

### UX改善
- [ ] 6桁入力完了時の自動送信
- [ ] カウントダウンタイマー表示
- [ ] 1桁ずつの入力フィールド
- [ ] 入力時のアニメーション

### セキュリティ強化
- [ ] IPアドレス制限
- [ ] デバイス認証
- [ ] 異常検知アラート

---

最終更新: 2025-06-18