# StockRx マイグレーションフレームワーク

## 概要

StockRxのマイグレーションフレームワークは、本番環境での安全なデータベース操作を実現するための包括的なツールセットです。

## 主要機能

### 1. 可逆的マイグレーション（ReversibleMigration）
- 全ての操作に対する自動ロールバック機能
- トランザクション管理とセーブポイントサポート
- エラー時の自動復旧

### 2. 動的負荷制御（LoadControlledMigration）
- システム負荷に応じたバッチサイズの自動調整
- CPU/メモリ使用率ベースのスロットリング
- 進捗状況のリアルタイム表示

### 3. 監視システム（MigrationMonitor）
- リアルタイム進捗追跡
- パフォーマンスメトリクスの収集
- 異常検知とアラート通知

### 4. 分散ロック（MigrationLock）
- 複数サーバーでの同時実行防止
- Redisベース/データベースベースのロック機構
- デッドロック検出と自動解放

## 使用方法

### 基本的な可逆マイグレーション

```ruby
class AddIndexToInventories < ReversibleMigration
  protected

  def execute_with_rollback_support
    # インデックスを追加（自動的にロールバック可能）
    add_index :inventories, :name
    add_index :inventories, [:status, :created_at]
  end
end
```

### 負荷制御付きデータ処理

```ruby
class UpdateInventoryPrices < LoadControlledMigration
  protected

  def execute_with_rollback_support
    # 設定をカスタマイズ
    configure_load_control(
      initial_batch_size: 500,
      cpu_threshold: 60,
      memory_threshold: 70
    )

    # 大量データの更新（自動的に負荷制御）
    update_records(
      Inventory,
      { price: nil },
      { price: 0 }
    )
  end
end
```

### 複雑なマイグレーション例

```ruby
class MigrateInventoryData < LoadControlledMigration
  protected

  def execute_with_rollback_support
    # 分散ロックで同時実行を防止
    MigrationLock.with_lock("migrate_inventory_data") do
      # 監視を開始
      monitor_key = MigrationMonitor.start_monitoring(
        "inventory_data_migration",
        total_records: Inventory.count
      )

      # データ移行処理
      migrate_inventory_data

      # 監視を終了
      MigrationMonitor.stop_monitoring(monitor_key)
    end
  end

  private

  def migrate_inventory_data
    processed = 0
    
    Inventory.find_in_batches(batch_size: @current_batch_size) do |batch|
      batch.each do |inventory|
        # 複雑な処理をリトライ付きで実行
        with_retry do
          process_inventory(inventory)
        end
        
        processed += 1
      end
      
      # 進捗を更新
      MigrationMonitor.update_progress(monitor_key, processed)
      
      # 動的負荷制御を適用
      apply_dynamic_load_control
    end
  end
end
```

## 設定オプション

### LoadControlledMigration

| オプション | デフォルト値 | 説明 |
|----------|-----------|------|
| initial_batch_size | 1000 | 初期バッチサイズ |
| min_batch_size | 100 | 最小バッチサイズ |
| max_batch_size | 10000 | 最大バッチサイズ |
| cpu_threshold | 70 | CPU使用率の閾値（%） |
| memory_threshold | 80 | メモリ使用率の閾値（%） |
| query_time_threshold | 5 | クエリ実行時間の閾値（秒） |

### MigrationLock

| オプション | デフォルト値 | 説明 |
|----------|-----------|------|
| timeout | 5分 | ロックのタイムアウト |
| retry_count | 3 | リトライ回数 |
| retry_delay | 1秒 | リトライ間隔 |

## ベストプラクティス

### 1. 小さなバッチで処理
```ruby
# Good: 適切なバッチサイズで処理
create_records(Inventory, data, batch_size: 500)

# Bad: 全データを一度に処理
Inventory.create!(data)  # 大量データでメモリ枯渇の可能性
```

### 2. データ整合性の検証
```ruby
def run_custom_validations
  # 外部キー制約の確認
  unless foreign_key_exists?(:inventories, :categories)
    raise "Foreign key constraint missing"
  end
  
  # カスタムバリデーション
  invalid_count = Inventory.where("price < 0").count
  if invalid_count > 0
    raise "Found #{invalid_count} inventories with invalid prices"
  end
end
```

### 3. 適切なエラーハンドリング
```ruby
def process_record(record)
  with_retry(max_attempts: 3) do
    # 処理実行
    record.update!(processed: true)
  end
rescue => e
  # エラーをログに記録し、処理を継続
  Rails.logger.error "Failed to process record #{record.id}: #{e.message}"
  MigrationMonitor.update_progress(
    monitor_key, 
    processed_count,
    error: e.message,
    record_id: record.id
  )
end
```

## トラブルシューティング

### ロールバックが失敗する場合
1. ログを確認: `log/migrations/`ディレクトリ
2. 手動でロールバック: `migration.execute_rollback`
3. データベースの状態を確認

### パフォーマンスが低い場合
1. バッチサイズを調整
2. インデックスの有無を確認
3. 他のプロセスとの競合を確認

### メモリ不足エラー
1. バッチサイズを減らす
2. `find_each`や`find_in_batches`を使用
3. GCを明示的に実行

## 今後の拡張予定

- Prometheusメトリクス連携
- Grafanaダッシュボード
- 機械学習による最適化
- ゼロダウンタイムデプロイメント対応