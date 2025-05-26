# StockRx ActionCable統合ガイド

## 概要

StockRxアプリケーションでは、リアルタイム通信機能としてActionCableを統合し、バックグラウンドジョブの進捗表示や管理者への即座な通知を実現しています。

## 機能一覧

### 1. CSVインポート進捗表示
- リアルタイムでの進捗バー更新
- エラー時の即座の通知
- ジョブ完了時の自動リダイレクト

### 2. 月次レポート生成進捗
- 複数段階での進捗更新
- 各処理ステップの詳細表示
- 生成完了時の通知

### 3. 在庫アラート通知
- 低在庫時の即座な通知
- 期限切れ商品の警告
- システムメンテナンス通知

## アーキテクチャ

```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Admin UI      │    │ ActionCable  │    │ Background Job  │
│   (JavaScript)  │◄──►│   Server     │◄──►│ (Sidekiq)       │
└─────────────────┘    └──────────────┘    └─────────────────┘
         │                      │                     │
         │                      │                     │
         ▼                      ▼                     ▼
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│ Stimulus        │    │ AdminChannel │    │ ProgressNotifier│
│ Controller      │    │              │    │ Module          │
└─────────────────┘    └──────────────┘    └─────────────────┘
```

## 実装詳細

### 1. AdminChannel設定

管理者専用のチャンネルで、認証されたユーザーのみがアクセス可能：

```ruby
# app/channels/admin_channel.rb
class AdminChannel < ApplicationCable::Channel
  def subscribed
    reject unless current_admin
    stream_for current_admin
  end
  
  def track_csv_import(data)
    # CSV進捗追跡の開始
  end
end
```

### 2. ProgressNotifier モジュール

バックグラウンドジョブで共通利用可能な進捗通知機能：

```ruby
# app/lib/progress_notifier.rb
module ProgressNotifier
  def initialize_progress(admin_id, job_id, job_type, metadata = {})
    # 進捗追跡の初期化
  end
  
  def update_progress(status_key, admin_id, job_type, progress, message = nil)
    # 進捗更新の通知
  end
end
```

### 3. フロントエンド統合

Stimulusコントローラーでリアルタイム更新を処理：

```javascript
// app/javascript/controllers/import_progress_controller.js
export default class extends Controller {
  connect() {
    this.setupActionCable()
  }
  
  onMessageReceived(data) {
    switch (data.type) {
      case "csv_import_progress":
        this.updateProgressBar(data.progress)
        break
    }
  }
}
```

## 使用方法

### 1. 新しいジョブでの進捗通知

```ruby
class YourCustomJob < ApplicationJob
  include ProgressNotifier
  
  def perform(admin_id, data)
    job_id = SecureRandom.uuid
    status_key = initialize_progress(admin_id, job_id, "your_job_type")
    
    # 処理の各段階で進捗を更新
    update_progress(status_key, admin_id, "your_job_type", 25, "処理中...")
    # ... 実際の処理 ...
    
    notify_completion(status_key, admin_id, "your_job_type", result_data)
  end
end
```

### 2. フロントエンドでの進捗表示

```erb
<!-- app/views/admin/your_feature.html.erb -->
<div data-controller="import-progress" 
     data-import-progress-job-id-value="<%= @job_id %>"
     data-import-progress-admin-id-value="<%= current_admin.id %>">
  
  <div data-import-progress-target="bar"></div>
  <div data-import-progress-target="status"></div>
</div>
```

## セキュリティ対策

### 1. 認証・認可
- AdminChannelは認証済み管理者のみアクセス可能
- 各管理者は自分のデータのみ受信
- セッション情報による認証確認

### 2. データ保護
- Redis上の進捗データは暗号化
- ファイルパスなど機密情報は除去
- 適切な有効期限設定

### 3. 接続管理
- 異常切断時の自動再接続
- レート制限によるDDoS対策
- 不正アクセスの監視

## テスト戦略

### 1. 単体テスト
```ruby
# spec/channels/admin_channel_spec.rb
RSpec.describe AdminChannel, type: :channel do
  it "subscribes to admin stream when authenticated" do
    stub_connection current_admin: admin
    subscribe
    expect(subscription).to be_confirmed
  end
end
```

### 2. 統合テスト
```ruby
# spec/features/csv_import_spec.rb
scenario 'shows progress updates during import with ActionCable' do
  # ActionCable通信のテスト
end
```

### 3. パフォーマンステスト
- 同時接続数の負荷テスト
- メッセージ配信遅延の測定
- メモリ使用量の監視

## パフォーマンス最適化

### 1. コネクション管理
- 適切なコネクションプール設定
- 不要な接続の自動切断
- 接続状況の監視

### 2. メッセージ最適化
- バッチ通知による負荷軽減
- 重要度に応じた配信頻度調整
- 圧縮による転送量削減

### 3. スケーラビリティ
- Redis Pub/Subによる分散対応
- ロードバランサー対応
- 水平スケーリング対応

## 監視・運用

### 1. ログ・メトリクス
- 接続数・切断数の追跡
- メッセージ配信ログ
- エラー率の監視

### 2. アラート設定
- 接続異常の検知
- 配信失敗の通知
- パフォーマンス劣化の警告

### 3. 障害対応
- フォールバック機能（ポーリング）
- 自動復旧メカニズム
- 手動介入手順

## 今後の拡張計画

### 1. 機能拡張（優先度：高）
- [ ] 複数管理者間での協調作業通知
- [ ] チーム単位でのチャンネル分離
- [ ] より詳細な進捗表示（サブタスク対応）

### 2. UX改善（優先度：中）
- [ ] 進捗表示のアニメーション強化
- [ ] 音声・デスクトップ通知対応
- [ ] モバイル端末最適化

### 3. 運用改善（優先度：中）
- [ ] 自動スケーリング機能
- [ ] より詳細な監視ダッシュボード
- [ ] パフォーマンス自動調整

### 4. セキュリティ強化（優先度：高）
- [ ] エンドツーエンド暗号化
- [ ] より厳格な認証機能
- [ ] 監査ログの詳細化

## トラブルシューティング

### よくある問題と解決方法

1. **ActionCable接続が確立されない**
   - セッション認証の確認
   - ブラウザのWebSocket対応状況
   - サーバー側のケーブル設定確認

2. **進捗が更新されない**
   - Redisの接続状況確認
   - ジョブの実行状況確認
   - JavaScript console エラーの確認

3. **パフォーマンスが劣化する**
   - 同時接続数の確認
   - メモリ使用量の監視
   - Redis性能の確認

## 参考資料

- [Rails ActionCable Guide](https://guides.rubyonrails.org/action_cable_overview.html)
- [Stimulus Handbook](https://stimulus.hotwired.dev/handbook/introduction)
- [Redis Documentation](https://redis.io/documentation)
- [Sidekiq Best Practices](https://github.com/mperham/sidekiq/wiki/Best-Practices) 