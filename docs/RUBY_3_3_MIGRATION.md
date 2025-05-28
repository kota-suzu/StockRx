# Ruby 3.3移行ガイド

## 完了済み修正

### 1. Net::TimeoutError廃止への対応 ✅
- **問題**: Ruby 3.3で`Net::TimeoutError`が削除され、`Timeout::Error`に統合
- **修正箇所**:
  - `app/jobs/external_api_sync_job.rb`: `retry_on Net::TimeoutError` → `retry_on Timeout::Error`
  - `app/jobs/application_job.rb`: TODOコメント内の参照更新

### 2. Faraday依存関係の整理 ✅
- **問題**: 未実装機能でのFaraday参照によるNameError
- **修正箇所**:
  - `app/jobs/external_api_sync_job.rb`: Faraday関連のエラーハンドリングをコメントアウト
  - 将来の実装に備えた適切なTODOコメント追加

### 3. 横展開確認済み ✅
- 全ジョブファイルでNet::TimeoutErrorの使用箇所を確認
- 他に問題となる箇所は発見されず

## TODO: 今後必要な対応（優先度：高）

### 1. CI環境でのMySQL接続問題
- **現状**: GitHub Actions環境でのデータベース接続認証エラー
- **対応方法**:
  ```yaml
  # .github/workflows/test.yml での対応例
  services:
    mysql:
      image: mysql:8.0
      env:
        MYSQL_ROOT_PASSWORD: password
        MYSQL_DATABASE: app_test
      options: >-
        --health-cmd="mysqladmin ping"
        --health-interval=10s
        --health-timeout=5s
        --health-retries=3
  ```

### 2. Ruby 3.3互換性チェック
- **gemfile内のgem互換性確認**:
  - `mysql2`: Ruby 3.3対応済み確認
  - `sidekiq`: 最新版での動作確認
  - `redis`: 接続プール設定の見直し

### 3. 本番環境での包括的テスト
- **パフォーマンステスト**:
  - Ruby 3.3での性能測定
  - メモリ使用量の変化確認
  - ガベージコレクション動作の確認

## ベストプラクティス

### 1. エラーハンドリングの統一
```ruby
# Ruby 3.3以降推奨
retry_on Timeout::Error, wait: :exponentially_longer, attempts: 5

# 廃止予定（Ruby 3.2以前のみ）
# retry_on Net::TimeoutError, wait: :exponentially_longer, attempts: 5
```

### 2. CI環境での設定最適化
```yaml
# database.yml テスト環境
test:
  adapter: mysql2
  database: app_test
  username: root
  password: password
  host: <%= ENV.fetch("DATABASE_HOST", "127.0.0.1") %>
  port: <%= ENV.fetch("DATABASE_PORT", 3306) %>
```

### 3. ログ監視の強化
- Ruby 3.3での新しい警告メッセージの監視
- 非推奨メソッドの使用検出
- パフォーマンスメトリクスの追跡

## 関連ドキュメント
- [Ruby 3.3 Release Notes](https://www.ruby-lang.org/en/news/2023/12/25/ruby-3-3-0-released/)
- [Net::TimeoutError Migration Guide](https://bugs.ruby-lang.org/issues/20042)
- [Rails 8.0 Compatibility](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html)