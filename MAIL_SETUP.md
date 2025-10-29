# 📧 開発環境メール設定ガイド

StockRx開発環境でのメール送信テスト方法をまとめています。

## 🚀 クイックスタート

### 1. Gemの追加
```bash
bundle install
```

### 2. 設定済みのメール配信方法から選択

## 📨 配信方法の比較

| 方法 | 特徴 | 推奨用途 | URL |
|------|------|----------|-----|
| **Letter Opener** | ブラウザ自動表示 | 簡単テスト | 自動で開く |
| **Letter Opener Web** | Web UI確認 | 履歴確認 | http://localhost:3000/letter_opener |
| **MailHog** | 本格SMTP | 本番類似環境 | http://localhost:8025 |
| **Docker MailTrap** | コンテナ版 | チーム開発 | http://localhost:8025 |

## 🔧 設定方法

### 方法1: Letter Opener（デフォルト・推奨）

最も簡単。メールが自動でブラウザに表示されます。

```bash
# すでに設定済み - 何もする必要なし
rails server
ruby test_mail_delivery.rb
```

### 方法2: MailHog（SMTP サーバー）

実際のSMTPサーバーを模擬できます。

```bash
# インストール
brew install mailhog

# 起動
mailhog

# 別ターミナルで
MAIL_DELIVERY_METHOD=smtp ruby test_mail_delivery.rb

# Web UI確認
open http://localhost:8025
```

### 方法3: Docker MailTrap

チーム開発で統一環境を使いたい場合。

```bash
# 起動
docker-compose --profile dev up mailtrap

# 別ターミナルで  
MAIL_DELIVERY_METHOD=smtp ruby test_mail_delivery.rb

# Web UI確認
open http://localhost:8025
```

## 🧪 テスト実行

### 基本テスト
```bash
# Letter Opener で確認
ruby test_mail_delivery.rb

# SMTP サーバーで確認
MAIL_DELIVERY_METHOD=smtp ruby test_mail_delivery.rb

# ログ出力で確認
MAIL_DELIVERY_METHOD=log ruby test_mail_delivery.rb
```

### 個別機能テスト

#### CSVインポート完了メール
```bash
rails console
AdminMailer.csv_import_complete(Admin.first, {
  valid_count: 100,
  invalid_records: []
}).deliver_now
```

#### 在庫アラートメール
```bash
rails console
low_stock_items = Inventory.limit(5)
AdminMailer.stock_alert(Admin.first, low_stock_items, 10).deliver_now
```

#### セキュリティアラート
```bash
rails console
AdminMailer.system_error_alert(Admin.first, {
  error_class: "SecurityError",
  error_message: "テストアラート",
  occurred_at: Time.current
}).deliver_now
```

## 🔍 トラブルシューティング

### Letter Opener でメールが表示されない
```bash
# 設定確認
rails console
Rails.application.config.action_mailer.delivery_method
# => :letter_opener が表示されることを確認
```

### MailHog に接続できない
```bash
# MailHog プロセス確認
ps aux | grep mailhog

# ポート確認
netstat -an | grep 1025  # SMTP
netstat -an | grep 8025  # Web UI

# 再起動
killall mailhog
mailhog
```

### Docker で起動しない
```bash
# プロファイル確認
docker-compose config --profile dev

# ログ確認
docker-compose --profile dev logs mailtrap

# 再ビルド
docker-compose --profile dev up --build mailtrap
```

## 📊 メール内容の確認方法

### Letter Opener
- 自動でブラウザに表示
- http://localhost:3000/letter_opener で履歴確認

### MailHog/MailTrap
- http://localhost:8025 にアクセス
- 送信されたメール一覧が表示
- メール詳細、HTML/テキスト表示切り替え可能

### ログ出力
```bash
tail -f log/development.log | grep -A 20 "Sent mail"
```

## 🎯 本番環境準備

開発テストが完了したら、本番環境設定：

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: ENV["SMTP_ADDRESS"],
  port: ENV["SMTP_PORT"],
  domain: ENV["SMTP_DOMAIN"],
  user_name: ENV["SMTP_USERNAME"],
  password: ENV["SMTP_PASSWORD"],
  authentication: "plain",
  enable_starttls_auto: true
}
```

## 🔒 セキュリティ考慮事項

- **開発環境のみ**: Letter Opener は開発環境専用
- **認証情報**: 本番SMTP設定は環境変数で管理
- **メール内容**: 機密情報を含むメールのテスト時は注意

## 💡 よくある使い方

### デバッグ時
```bash
# ログで内容確認
MAIL_DELIVERY_METHOD=log ruby test_mail_delivery.rb

# ファイルで詳細確認  
MAIL_DELIVERY_METHOD=letter_opener ruby test_mail_delivery.rb
```

### デモ準備時
```bash
# 見た目確認
MAIL_DELIVERY_METHOD=letter_opener ruby test_mail_delivery.rb

# SMTP動作確認
MAIL_DELIVERY_METHOD=smtp ruby test_mail_delivery.rb
```

### CI/CD
```bash
# テスト環境
MAIL_DELIVERY_METHOD=test ruby test_mail_delivery.rb
```

---

## 📞 サポート

問題が発生した場合：
1. このドキュメントのトラブルシューティングを確認
2. ログファイル（`log/development.log`）を確認
3. 設定ファイル（`config/environments/development.rb`）を確認 