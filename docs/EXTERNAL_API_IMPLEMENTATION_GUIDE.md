# 外部API連携実装ガイド

## 現状

`external_api_sync_job.rb`は現在スケルトン実装で、実際のHTTPクライアントは未実装です。

## 実装手順

### 1. 依存関係の追加

```ruby
# Gemfile
gem "faraday", "~> 2.7"           # HTTPクライアント
gem "faraday-retry", "~> 2.2"     # リトライ機能
gem "faraday-multipart", "~> 1.0" # マルチパート対応
```

### 2. エラーハンドリングの有効化

`app/jobs/external_api_sync_job.rb`で以下のコメントアウトを解除:

```ruby
# 現在コメントアウト中の箇所を有効化
retry_on Faraday::ConnectionFailed, wait: 60.seconds, attempts: 3
discard_on Faraday::UnauthorizedError
discard_on Faraday::ForbiddenError
```

### 3. HTTPクライアント実装例

```ruby
def fetch_with_retry(url, headers = {}, max_retries = 3)
  retries = 0

  begin
    connection = Faraday.new do |conn|
      conn.request :retry, max: max_retries, interval: 0.5
      conn.adapter Faraday.default_adapter
    end
    
    response = connection.get(url) do |req|
      headers.each { |key, value| req.headers[key] = value }
    end
    
    JSON.parse(response.body)
  rescue Faraday::Error => e
    Rails.logger.error "API request failed: #{e.message}"
    raise e
  end
end
```

### 4. セキュリティ考慮事項

#### 認証
- API トークンは環境変数で管理
- 定期的なトークンローテーション実装

#### レート制限
- API プロバイダーのレート制限遵守
- 適切な待機時間とバックオフ戦略

#### エラーログ
- 機密情報の除外
- 構造化ログ出力

### 5. 監視・アラート

#### メトリクス
- API 応答時間
- 成功/失敗率
- リトライ回数

#### アラート条件
- 連続失敗回数の閾値
- レスポンス時間の異常
- レート制限エラー

## テスト戦略

### 1. 単体テスト
```ruby
# spec/jobs/external_api_sync_job_spec.rb
RSpec.describe ExternalApiSyncJob do
  describe '#perform' do
    context 'when API responds successfully' do
      it 'processes data correctly' do
        # WebMock を使用してAPI応答をモック
      end
    end
    
    context 'when API returns error' do
      it 'handles error gracefully' do
        # エラーレスポンスのテスト
      end
    end
  end
end
```

### 2. 統合テスト
- サンドボックス環境での実際のAPI呼び出し
- エラーシナリオの検証

## パフォーマンス最適化

### 1. 並行処理
- Sidekiq の並行ワーカー活用
- API ごとの専用キュー設定

### 2. キャッシュ戦略
- 頻繁にアクセスするデータのRedisキャッシュ
- 適切なTTL設定

### 3. バッチ処理
- 大量データの分割処理
- メモリ使用量の最適化

## 運用フェーズでの監視

### 1. ログ監視
- 構造化ログでの異常検知
- ダッシュボードでの可視化

### 2. メトリクス監視
- Prometheus/Grafana での監視
- SLA メトリクスの追跡

### 3. 障害対応
- エスカレーション手順
- ロールバック戦略

## 関連ドキュメント
- [Faraday公式ドキュメント](https://lostisland.github.io/faraday/)
- [Sidekiq Best Practices](https://github.com/mperham/sidekiq/wiki/Best-Practices)
- [Rails API 設計ガイド](https://guides.rubyonrails.org/api_app.html)