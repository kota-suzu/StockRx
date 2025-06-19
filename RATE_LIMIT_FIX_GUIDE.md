# 🔧 レート制限エラー修正ガイド

## エラー内容

```
ArgumentError: Unknown rate limit type: email_auth
```

## 原因

`EmailAuthController`が使用する`email_auth`レート制限タイプが`RateLimiter`サービスに未定義でした。

## 修正内容

### 1. RateLimiterサービス修正
```ruby
# app/services/rate_limiter.rb
LIMITS = {
  # ... 既存の設定 ...
  
  # メール認証（パスコード送信）
  email_auth: {
    limit: 3,        # 1時間に3回まで
    period: 1.hour,  # 計測期間
    block_duration: 1.hour  # ブロック時間
  },
  
  # ... 他の設定 ...
}.freeze
```

### 2. RateLimitableモジュール修正
```ruby
# app/controllers/concerns/rate_limitable.rb
case rate_limit_key_type
when :email_auth
  "パスコード送信回数が上限に達しました。#{minutes}分後に再度お試しください。"
# ... 他のケース ...
end
```

## メタ認知的設計判断

1. **レート制限値の根拠**
   - EmailAuthServiceの既存設定と整合性を保持（3回/時間）
   - password_resetと同レベルのセキュリティ設定
   - ユーザビリティとセキュリティのバランス

2. **横展開確認**
   - 他の認証系機能（login, password_reset）と一貫性
   - エラーメッセージの統一的な表現
   - ブロック時間の適切性

## テスト方法

### 1. 正常動作確認
```bash
# サーバー再起動
docker-compose restart web

# ブラウザアクセス
http://localhost:3000/store/sign_in?store_slug=st001
```

### 2. レート制限テスト
1. パスコード送信を4回連続実行
2. 3回目まで成功、4回目でエラー表示確認
3. エラーメッセージ: 「パスコード送信回数が上限に達しました。60分後に再度お試しください。」

### 3. Railsコンソール確認
```ruby
# レート制限状態確認
limiter = RateLimiter.new(:email_auth, "test_identifier")
limiter.allowed?  # => true
limiter.current_count  # => 0

# 手動でテスト
3.times { limiter.track! }
limiter.allowed?  # => false
limiter.time_until_unblock  # => 3600 (秒)
```

## セキュリティ考慮事項

### 実装された保護機能
- **ブルートフォース対策**: 1時間に3回の制限
- **DoS攻撃対策**: IPアドレスベースの制限
- **ユーザー列挙対策**: 存在しないメールでも同じレスポンス

### 今後の改善案（TODO）
```ruby
# TODO: 🟡 Phase 3（推奨）- レート制限の高度化
# - デイリー制限の追加実装（10回/日）
# - IPアドレスとメールアドレスの組み合わせ制限
# - 地理的位置による動的制限
# 横展開: 他の認証機能でも同様の高度化適用
```

## 関連ファイル

- `app/services/rate_limiter.rb`
- `app/controllers/concerns/rate_limitable.rb`
- `app/controllers/store_controllers/email_auth_controller.rb`
- `app/services/email_auth_service.rb`

---

修正日: 2025-06-18  
CLAUDE.md準拠実装