# 設定管理システム設計書

## 1. 概要

### 1.1 背景と課題

現在のStockRxアプリケーションでは、設定値が以下のような形で分散している：

- ハードコーディングされた定数（在庫アラート閾値、有効期限チェック日数など）
- 環境変数での管理
- Railsの設定ファイル（config/*.yml）
- 個別のモデル・ジョブ内での定義

この分散した設定管理は以下の問題を引き起こしている：

1. **運用時の柔軟性不足**: 設定変更にコードのデプロイが必要
2. **管理の複雑性**: 設定がどこで定義されているか把握しづらい
3. **一貫性の欠如**: 同じ種類の設定でも管理方法が異なる
4. **監査性の低さ**: 設定変更の履歴が追跡できない

### 1.2 目的

本設計書では、以下を実現する統一的な設定管理システムを提案する：

- 動的な設定変更（再起動不要）
- 設定の一元管理
- 変更履歴の追跡
- 型安全性とバリデーション
- パフォーマンスを考慮したキャッシング

## 2. 設計方針

### 2.1 基本原則

1. **段階的アプローチ**: 既存システムを段階的に移行
2. **後方互換性**: 既存の設定方法も当面サポート
3. **シンプルさ**: 過度な抽象化を避ける
4. **テスタビリティ**: テスト環境での設定上書きを容易に
5. **セキュリティ**: 機密情報の適切な管理

### 2.2 スコープ

#### 対象とする設定

- 在庫アラート閾値
- 有効期限チェック日数
- バッチ処理のサイズ
- ログ保持期間
- ジョブのスケジュール設定
- 通知設定のデフォルト値
- フィーチャーフラグ

#### 対象外

- データベース接続情報
- 外部API認証情報
- アプリケーションシークレット

## 3. アーキテクチャ

### 3.1 全体構成

```
┌─────────────────────────────────────────────────────┐
│                  Admin UI                           │
│              (設定管理画面)                          │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│             ConfigurationService                    │
│         (設定の読み書きインターフェース)              │
└──────────────────────┬──────────────────────────────┘
                       │
         ┌─────────────┴─────────────┐
         │                           │
┌────────▼────────┐         ┌───────▼────────┐
│ SystemSetting   │         │   Rails Cache   │
│    (Model)      │         │   (Redis)       │
└────────┬────────┘         └────────────────┘
         │
┌────────▼────────┐
│   PostgreSQL    │
│   (永続化層)     │
└─────────────────┘
```

### 3.2 コンポーネント設計

#### 3.2.1 SystemSetting モデル

```ruby
# app/models/system_setting.rb
class SystemSetting < ApplicationRecord
  # カテゴリ定義
  CATEGORIES = {
    inventory: '在庫管理',
    job: 'ジョブ設定',
    notification: '通知設定',
    system: 'システム設定'
  }.freeze

  # データ型定義
  DATA_TYPES = %w[string integer float boolean json datetime].freeze

  # バリデーション
  validates :key, presence: true, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES.keys.map(&:to_s) }
  validates :data_type, inclusion: { in: DATA_TYPES }
  
  # 型変換
  def typed_value
    case data_type
    when 'integer' then value.to_i
    when 'float' then value.to_f
    when 'boolean' then ActiveModel::Type::Boolean.new.cast(value)
    when 'json' then JSON.parse(value)
    when 'datetime' then Time.parse(value)
    else value
    end
  end

  # スコープ
  scope :by_category, ->(category) { where(category: category) }
  scope :active, -> { where(active: true) }
end
```

#### 3.2.2 データベーススキーマ

```ruby
# db/migrate/xxx_create_system_settings.rb
class CreateSystemSettings < ActiveRecord::Migration[7.0]
  def change
    create_table :system_settings do |t|
      t.string :key, null: false, index: { unique: true }
      t.string :category, null: false
      t.string :data_type, null: false, default: 'string'
      t.text :value
      t.text :default_value
      t.text :description
      t.jsonb :validation_rules, default: {}
      t.boolean :active, default: true
      t.boolean :encrypted, default: false
      t.references :updated_by, foreign_key: { to_table: :admins }
      
      t.timestamps
    end

    add_index :system_settings, :category
    add_index :system_settings, [:category, :active]
  end
end
```

#### 3.2.3 ConfigurationService

```ruby
# app/services/configuration_service.rb
class ConfigurationService
  include Singleton

  CACHE_TTL = 5.minutes

  class << self
    delegate :get, :set, :reload!, to: :instance
  end

  def initialize
    @mutex = Mutex.new
  end

  def get(key, default: nil)
    cached_value = Rails.cache.read(cache_key(key))
    return cached_value if cached_value.present?

    setting = SystemSetting.active.find_by(key: key)
    return default if setting.nil?

    value = setting.typed_value
    Rails.cache.write(cache_key(key), value, expires_in: CACHE_TTL)
    value
  rescue => e
    Rails.logger.error("Configuration fetch error: #{e.message}")
    default
  end

  def set(key, value, updated_by: nil)
    @mutex.synchronize do
      setting = SystemSetting.find_or_initialize_by(key: key)
      
      # 変更履歴の記録
      if setting.persisted? && setting.value != value.to_s
        ConfigurationChangeLog.create!(
          setting: setting,
          old_value: setting.value,
          new_value: value.to_s,
          changed_by: updated_by
        )
      end

      setting.update!(value: value.to_s, updated_by: updated_by)
      Rails.cache.delete(cache_key(key))
      broadcast_change(key, value)
    end
  end

  def reload!
    Rails.cache.delete_matched("config:*")
  end

  private

  def cache_key(key)
    "config:#{key}"
  end

  def broadcast_change(key, value)
    ActionCable.server.broadcast(
      "configuration_changes",
      { key: key, value: value, timestamp: Time.current }
    )
  end
end
```

#### 3.2.4 設定変更履歴

```ruby
# app/models/configuration_change_log.rb
class ConfigurationChangeLog < ApplicationRecord
  belongs_to :setting, class_name: 'SystemSetting'
  belongs_to :changed_by, class_name: 'Admin', optional: true

  validates :old_value, presence: true
  validates :new_value, presence: true

  scope :recent, -> { order(created_at: :desc).limit(100) }
end
```

### 3.3 設定の階層構造

```yaml
# 設定キーの命名規則
inventory:
  alert:
    low_stock_threshold: 10
    critical_stock_threshold: 5
  expiry:
    check_days_ahead: 30
    warning_days: 7

job:
  import:
    batch_size: 1000
    max_file_size_mb: 100
  cleanup:
    retention_days: 90
    batch_size: 1000
  
notification:
  email:
    default_enabled: true
    batch_size: 50
  slack:
    default_enabled: false
    webhook_url: "encrypted"
```

## 4. 実装計画

### 4.1 フェーズ1: 基盤構築（2週間）

1. SystemSettingモデルの実装
2. ConfigurationServiceの実装
3. 基本的なCRUD機能
4. キャッシング機構
5. テストの作成

### 4.2 フェーズ2: 既存設定の移行（1週間）

1. ジョブの設定値を移行
2. 環境変数からの段階的移行
3. 後方互換性の確保

### 4.3 フェーズ3: 管理UI（1週間）

1. 管理画面の実装
2. 設定のグループ化表示
3. 変更履歴の表示
4. バリデーションUI

### 4.4 フェーズ4: 高度な機能（2週間）

1. 設定のインポート/エクスポート
2. 環境別設定の管理
3. 設定変更の通知
4. A/Bテスト対応

## 5. 使用例

### 5.1 設定の取得

```ruby
# ジョブ内での使用例
class StockAlertJob < ApplicationJob
  def perform
    threshold = ConfigurationService.get(
      'inventory.alert.low_stock_threshold',
      default: 10
    )
    
    Inventory.where('quantity <= ?', threshold).find_each do |inventory|
      # アラート処理
    end
  end
end
```

### 5.2 設定の更新

```ruby
# コントローラーでの使用例
class AdminControllers::SystemSettingsController < AdminControllers::BaseController
  def update
    ConfigurationService.set(
      params[:key],
      params[:value],
      updated_by: current_admin
    )
    
    redirect_to admin_system_settings_path, notice: '設定を更新しました'
  end
end
```

### 5.3 フィーチャーフラグ

```ruby
# フィーチャーフラグの使用
if ConfigurationService.get('features.new_search_enabled', default: false)
  # 新しい検索機能を使用
else
  # 従来の検索機能を使用
end
```

## 6. セキュリティ考慮事項

### 6.1 アクセス制御

- 設定の閲覧・変更は管理者権限が必要
- 重要な設定変更は2段階認証を要求
- APIキーなどの機密情報は暗号化して保存

### 6.2 監査ログ

- すべての設定変更を記録
- 変更者、変更日時、変更前後の値を保存
- 定期的な監査レポートの生成

### 6.3 暗号化

```ruby
# 機密設定の暗号化
class SystemSetting < ApplicationRecord
  attr_encrypted :value, 
    key: Rails.application.credentials.dig(:system_setting_encryption_key),
    if: :encrypted?
end
```

## 7. パフォーマンス考慮事項

### 7.1 キャッシング戦略

- 頻繁にアクセスされる設定は Redis にキャッシュ
- TTL は 5分（変更頻度とのバランス）
- 設定変更時は即座にキャッシュを無効化

### 7.2 データベースアクセス

- 起動時の一括読み込みオプション
- N+1問題を避けるための設計
- インデックスの適切な設定

## 8. テスト戦略

### 8.1 単体テスト

```ruby
# spec/services/configuration_service_spec.rb
RSpec.describe ConfigurationService do
  describe '#get' do
    context 'when setting exists' do
      it 'returns typed value' do
        create(:system_setting, key: 'test.number', value: '42', data_type: 'integer')
        expect(ConfigurationService.get('test.number')).to eq(42)
      end
    end
    
    context 'when setting does not exist' do
      it 'returns default value' do
        expect(ConfigurationService.get('non.existent', default: 'default')).to eq('default')
      end
    end
  end
end
```

### 8.2 統合テスト

- 設定変更がジョブの動作に反映されることを確認
- キャッシュの動作確認
- 並行アクセス時の整合性確認

## 9. 移行計画

### 9.1 既存設定の移行

```ruby
# lib/tasks/migrate_configurations.rake
namespace :config do
  desc "Migrate hardcoded configurations to SystemSetting"
  task migrate: :environment do
    migrations = [
      { key: 'inventory.alert.low_stock_threshold', value: 10, category: 'inventory' },
      { key: 'job.cleanup.retention_days', value: 90, category: 'job' },
      # ... 他の設定
    ]
    
    migrations.each do |config|
      SystemSetting.find_or_create_by(key: config[:key]) do |setting|
        setting.value = config[:value]
        setting.category = config[:category]
        setting.data_type = config[:value].class.name.downcase
      end
    end
  end
end
```

### 9.2 段階的移行

1. 新機能から ConfigurationService を使用開始
2. 既存コードを段階的に書き換え
3. 環境変数は当面併用（フォールバック）
4. 完全移行後に旧方式を削除

## 10. 今後の拡張

### 10.1 将来的な機能

- 設定のバージョニング
- 環境別設定のオーバーライド
- 設定テンプレート
- REST API での設定管理
- Webhook による外部連携

### 10.2 他システムとの統合

- Kubernetes ConfigMap との同期
- 外部設定管理サービスとの連携
- CI/CD パイプラインでの設定管理

## 11. リスクと対策

| リスク | 影響度 | 発生確率 | 対策 |
|--------|--------|----------|------|
| キャッシュの不整合 | 高 | 中 | TTL設定と即時無効化の併用 |
| 設定ミスによるシステム停止 | 高 | 低 | バリデーション強化、ロールバック機能 |
| パフォーマンス劣化 | 中 | 低 | 適切なキャッシング、監視強化 |
| 移行時の設定漏れ | 中 | 中 | 段階的移行、十分なテスト |

## 12. 決定事項と根拠

### なぜデータベースベースの設定管理か？

**Before**: 環境変数や設定ファイルでの管理を検討
**After**: データベースベースの設定管理を採用
**理由**: 
- 動的な変更が可能（再起動不要）
- 変更履歴の追跡が容易
- 権限管理との統合が自然
- バックアップ・リストアが既存の仕組みで対応可能

### なぜ階層的なキー構造か？

**Before**: フラットなキー構造（例: `stock_alert_threshold`）
**After**: 階層的なキー構造（例: `inventory.alert.low_stock_threshold`）
**理由**:
- 設定の論理的なグループ化が可能
- 名前空間の衝突を防げる
- 一括操作（カテゴリ単位の取得など）が容易
- 将来の拡張に対応しやすい

## 13. まとめ

本設計により、StockRxアプリケーションは以下を実現できる：

1. **運用の柔軟性向上**: コード変更なしでビジネスルールを調整可能
2. **管理の一元化**: すべての設定を統一的なインターフェースで管理
3. **監査性の向上**: 設定変更の完全な履歴を保持
4. **開発効率の向上**: 新しい設定の追加が容易

段階的な移行アプローチにより、既存システムへの影響を最小限に抑えながら、着実に設定管理の改善を進めることができる。