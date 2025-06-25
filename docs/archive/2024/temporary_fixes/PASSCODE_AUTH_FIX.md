# 🐛 パスコード認証エラー修正

## エラー内容

```
undefined method `id' for nil
```

認証成功後に`temp_password`オブジェクトがnilになるエラー

## 原因分析（メタ認知）

1. **EmailAuthService**: `temp_password`オブジェクトを返していなかった
2. **EmailAuthController**: エラー時のUI処理が不適切
3. **リダイレクト先**: 存在しないパスを参照

## 修正内容

### 1. EmailAuthService修正
```ruby
# 認証成功時の戻り値にtemp_passwordオブジェクトを追加
{
  success: true,
  temp_password_id: temp_password.id,
  temp_password: temp_password,  # 追加
  authenticated_at: Time.current
}
```

### 2. EmailAuthController修正

#### エラー時のリダイレクト
```ruby
def respond_to_verification_error(message, error_code)
  # ログイン画面に戻す
  redirect_to new_store_user_session_path(store_slug: @store&.slug),
              alert: message
end
```

#### 成功時のリダイレクト
```ruby
def respond_to_verification_success
  # 店舗ダッシュボードへ
  redirect_to store_dashboard_path(store_slug: @store.slug),
              notice: "ログインしました"
end
```

### 3. UI修正
- パスコード検証フォーム: `local: true`に変更（同期送信）

## 横展開確認

- 他の認証系サービスでも同様のオブジェクト返却パターン確認
- リダイレクト先の統一性確保
- エラーハンドリングの一貫性

## テスト手順

1. **サーバー再起動**
```bash
docker-compose restart web
```

2. **パスコード送信**
```
http://localhost:3000/store/sign_in?store_slug=st001
メール: yamada@central.example.com
```

3. **パスコード確認**
```
http://localhost:8025
```

4. **ログイン完了**
- 6桁パスコード入力
- 店舗ダッシュボードへリダイレクト確認

## セキュリティ考慮事項

- 認証成功後のtemp_passwordは使用済みマーク済み
- セッション情報に適切に保存
- 監査ログ記録済み

---

修正日: 2025-06-18
CLAUDE.md準拠実装