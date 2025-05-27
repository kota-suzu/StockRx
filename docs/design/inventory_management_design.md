# 在庫管理システム設計書

**最終更新**: 2025年5月28日  
**バージョン**: 1.0  
**ステータス**: 実装中

## 1. 概要

StockRxの在庫管理システムは、医薬品・医療機器の在庫を効率的に管理し、期限管理・ロット追跡・在庫最適化を実現するシステムです。

### 主要機能
- **在庫管理**: CRUD操作、検索、フィルタリング
- **バッチ管理**: ロット単位での追跡、FIFO/FEFO管理
- **期限管理**: 有効期限アラート、自動通知
- **在庫移動**: 入庫・出庫・移動履歴の完全追跡
- **レポート**: 在庫レポート、ABC分析、回転率分析

## 2. アーキテクチャ

### 2.1 データモデル

```ruby
# 在庫マスタ
class Inventory < ApplicationRecord
  # 基本情報
  validates :name, presence: true
  validates :sku, presence: true, uniqueness: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  
  # 関連
  has_many :batches, dependent: :destroy
  has_many :inventory_logs
  has_many :shipments
  has_many :receipts
  
  # スコープ
  scope :active, -> { where(status: :active) }
  scope :low_stock, -> { where('quantity <= reorder_point') }
  scope :expiring_soon, -> (days = 30) { 
    joins(:batches).where('batches.expiry_date <= ?', days.days.from_now)
  }
end

# バッチ（ロット）管理
class Batch < ApplicationRecord
  belongs_to :inventory
  
  validates :lot_number, presence: true, uniqueness: { scope: :inventory_id }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :expiry_date, presence: true
  
  scope :available, -> { where('quantity > 0').order(:expiry_date) }
  scope :expired, -> { where('expiry_date < ?', Date.current) }
end

# 在庫履歴
class InventoryLog < ApplicationRecord
  belongs_to :inventory
  belongs_to :batch, optional: true
  
  enum action: {
    created: 0,
    updated: 1,
    received: 2,
    shipped: 3,
    adjusted: 4,
    expired: 5,
    damaged: 6
  }
  
  validates :action, presence: true
  validates :quantity_change, presence: true
  validates :user, presence: true
end
```

### 2.2 ビジネスロジック層

```ruby
# app/services/inventory_service.rb
class InventoryService
  # 在庫受入処理
  def self.receive_stock(inventory, quantity, batch_params)
    ActiveRecord::Base.transaction do
      # バッチ作成
      batch = inventory.batches.create!(
        batch_params.merge(quantity: quantity)
      )
      
      # 在庫数更新
      inventory.increment!(:quantity, quantity)
      
      # 履歴記録
      InventoryLog.create!(
        inventory: inventory,
        batch: batch,
        action: :received,
        quantity_change: quantity,
        user: Current.admin.email
      )
      
      # 通知（必要に応じて）
      NotificationService.notify_stock_received(inventory, quantity)
      
      batch
    end
  end
  
  # 在庫払出処理（FIFO）
  def self.ship_stock(inventory, quantity)
    ActiveRecord::Base.transaction do
      remaining = quantity
      shipped_batches = []
      
      # FIFOでバッチから払出
      inventory.batches.available.each do |batch|
        break if remaining <= 0
        
        take_quantity = [batch.quantity, remaining].min
        batch.decrement!(:quantity, take_quantity)
        remaining -= take_quantity
        
        shipped_batches << {
          batch: batch,
          quantity: take_quantity
        }
      end
      
      raise InsufficientStockError if remaining > 0
      
      # 在庫数更新
      inventory.decrement!(:quantity, quantity)
      
      # 履歴記録
      shipped_batches.each do |shipped|
        InventoryLog.create!(
          inventory: inventory,
          batch: shipped[:batch],
          action: :shipped,
          quantity_change: -shipped[:quantity],
          user: Current.admin.email
        )
      end
      
      shipped_batches
    end
  end
end
```

## 3. 機能詳細

### 3.1 在庫検索・フィルタリング

```ruby
# app/services/inventory_search_service.rb
class InventorySearchService
  def initialize(params)
    @params = params
    @scope = Inventory.includes(:batches)
  end
  
  def execute
    apply_keyword_search
    apply_category_filter
    apply_status_filter
    apply_stock_level_filter
    apply_expiry_filter
    apply_sorting
    
    @scope
  end
  
  private
  
  def apply_keyword_search
    return unless @params[:q].present?
    
    keyword = "%#{@params[:q]}%"
    @scope = @scope.where(
      "name ILIKE :keyword OR sku ILIKE :keyword OR description ILIKE :keyword",
      keyword: keyword
    )
  end
  
  def apply_stock_level_filter
    case @params[:stock_level]
    when 'low'
      @scope = @scope.low_stock
    when 'out_of_stock'
      @scope = @scope.where(quantity: 0)
    when 'overstocked'
      @scope = @scope.where('quantity > maximum_stock')
    end
  end
end
```

### 3.2 期限管理

```ruby
# app/jobs/expiry_check_job.rb
class ExpiryCheckJob < ApplicationJob
  queue_as :default
  
  def perform
    # 期限切れチェック
    check_expired_batches
    
    # 期限間近チェック
    check_expiring_soon_batches
    
    # レポート生成
    generate_expiry_report
  end
  
  private
  
  def check_expired_batches
    Batch.where(
      'expiry_date < ? AND quantity > 0',
      Date.current
    ).find_each do |batch|
      # 期限切れ処理
      handle_expired_batch(batch)
    end
  end
  
  def check_expiring_soon_batches
    [30, 60, 90].each do |days|
      Batch.where(
        expiry_date: Date.current..days.days.from_now,
        quantity: 1..
      ).find_each do |batch|
        # 通知送信
        send_expiry_alert(batch, days)
      end
    end
  end
end
```

## 4. API設計

### 4.1 RESTful API

```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :inventories do
      member do
        post :receive
        post :ship
        post :adjust
        get :history
        get :batches
      end
      
      collection do
        get :search
        get :low_stock
        get :expiring_soon
        post :bulk_update
      end
    end
  end
end
```

### 4.2 APIレスポンス形式

```json
// GET /api/v1/inventories/:id
{
  "data": {
    "id": 1,
    "type": "inventory",
    "attributes": {
      "sku": "MED-001",
      "name": "アスピリン 100mg",
      "description": "解熱鎮痛剤",
      "quantity": 500,
      "unit": "錠",
      "price": 10.5,
      "reorder_point": 100,
      "maximum_stock": 1000,
      "status": "active"
    },
    "relationships": {
      "batches": {
        "data": [
          {
            "id": 10,
            "type": "batch",
            "attributes": {
              "lot_number": "LOT-2024-001",
              "quantity": 200,
              "expiry_date": "2025-12-31",
              "manufactured_date": "2024-01-15"
            }
          }
        ]
      }
    }
  },
  "meta": {
    "total_value": 5250.0,
    "average_age_days": 45,
    "turnover_rate": 12.5
  }
}
```

## 5. セキュリティ考慮事項

### 5.1 アクセス制御

```ruby
# app/policies/inventory_policy.rb
class InventoryPolicy < ApplicationPolicy
  def index?
    user.admin? || user.has_permission?(:view_inventory)
  end
  
  def create?
    user.admin? || user.has_permission?(:manage_inventory)
  end
  
  def update?
    user.admin? || user.has_permission?(:manage_inventory)
  end
  
  def destroy?
    user.admin?
  end
  
  def receive?
    user.admin? || user.has_permission?(:receive_inventory)
  end
  
  def ship?
    user.admin? || user.has_permission?(:ship_inventory)
  end
end
```

### 5.2 監査ログ

全ての在庫操作は`InventoryLog`に記録され、以下の情報を保持：
- 操作者（user）
- 操作日時（created_at）
- 操作内容（action）
- 数量変更（quantity_change）
- 関連バッチ（batch_id）
- 追加情報（metadata）

## 6. パフォーマンス最適化

### 6.1 インデックス戦略

```sql
-- 高頻度検索用インデックス
CREATE INDEX idx_inventories_sku ON inventories(sku);
CREATE INDEX idx_inventories_status ON inventories(status);
CREATE INDEX idx_inventories_quantity ON inventories(quantity);

-- バッチ検索用インデックス
CREATE INDEX idx_batches_expiry_date ON batches(expiry_date);
CREATE INDEX idx_batches_inventory_quantity ON batches(inventory_id, quantity);

-- 履歴検索用インデックス
CREATE INDEX idx_inventory_logs_inventory_created ON inventory_logs(inventory_id, created_at);
```

### 6.2 キャッシュ戦略

```ruby
# 在庫統計情報のキャッシュ
class Inventory < ApplicationRecord
  def statistics
    Rails.cache.fetch("inventory_stats_#{id}", expires_in: 1.hour) do
      {
        total_value: calculate_total_value,
        turnover_rate: calculate_turnover_rate,
        average_age: calculate_average_age
      }
    end
  end
end
```

## 7. テスト戦略

### 7.1 単体テスト

```ruby
# spec/models/inventory_spec.rb
RSpec.describe Inventory, type: :model do
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:sku) }
    it { should validate_uniqueness_of(:sku) }
  end
  
  describe 'scopes' do
    describe '.low_stock' do
      it 'returns inventories below reorder point' do
        low = create(:inventory, quantity: 50, reorder_point: 100)
        normal = create(:inventory, quantity: 200, reorder_point: 100)
        
        expect(Inventory.low_stock).to include(low)
        expect(Inventory.low_stock).not_to include(normal)
      end
    end
  end
end
```

### 7.2 統合テスト

```ruby
# spec/services/inventory_service_spec.rb
RSpec.describe InventoryService do
  describe '.ship_stock' do
    it 'ships stock using FIFO method' do
      inventory = create(:inventory, quantity: 300)
      old_batch = create(:batch, inventory: inventory, quantity: 100, 
                        expiry_date: 1.month.from_now)
      new_batch = create(:batch, inventory: inventory, quantity: 200,
                        expiry_date: 6.months.from_now)
      
      InventoryService.ship_stock(inventory, 150)
      
      expect(old_batch.reload.quantity).to eq(0)
      expect(new_batch.reload.quantity).to eq(150)
    end
  end
end
```

## 8. 実装ロードマップ

### Phase 1: 基本機能（完了）
- [x] 在庫マスタCRUD
- [x] 基本的な検索・フィルタリング
- [x] 在庫履歴記録

### Phase 2: バッチ管理（実装中）
- [ ] バッチ単位での在庫管理
- [ ] FIFO/FEFO払出ロジック
- [ ] ロット追跡機能

### Phase 3: 高度な機能（計画中）
- [ ] ABC分析
- [ ] 在庫回転率分析
- [ ] 自動発注点計算
- [ ] 需要予測

### Phase 4: 統合・最適化（将来）
- [ ] 外部システム連携
- [ ] モバイルアプリ対応
- [ ] リアルタイムダッシュボード

## 9. ベストプラクティス

### 9.1 在庫操作の原則

1. **トランザクション管理**: 全ての在庫操作は必ずトランザクション内で実行
2. **履歴記録**: 全ての変更は`InventoryLog`に記録
3. **検証**: ビジネスルールの厳格な検証
4. **通知**: 重要な変更は関係者に通知

### 9.2 エラーハンドリング

```ruby
class InsufficientStockError < StandardError; end
class InvalidBatchError < StandardError; end
class ExpiredBatchError < StandardError; end

# 使用例
begin
  InventoryService.ship_stock(inventory, quantity)
rescue InsufficientStockError => e
  # TODO: 在庫不足エラーの処理
  render_error 422, "在庫が不足しています"
rescue InvalidBatchError => e
  # TODO: 無効なバッチエラーの処理
  render_error 422, "指定されたバッチが無効です"
end
```

## 10. 参考資料

- [在庫管理のベストプラクティス](https://www.example.com)
- [医薬品在庫管理ガイドライン](https://www.example.com)
- [Rails在庫管理システム実装例](https://github.com/example)