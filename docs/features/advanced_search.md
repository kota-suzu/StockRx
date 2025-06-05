# 高度な検索機能ドキュメント

## 概要

StockRxの高度な検索機能は、Ransackを使用せずに複雑な検索条件を実現する独自実装です。この機能により、OR/AND条件の柔軟な組み合わせ、ポリモーフィック関連の検索、複数テーブルを跨いだクロステーブル検索が可能になります。

## アーキテクチャ

### 主要コンポーネント

1. **AdvancedSearchQuery** (`app/services/advanced_search_query.rb`)
   - 検索条件を構築する中心的なサービスクラス
   - メソッドチェーンによる直感的なクエリ構築をサポート
   - 各種条件ビルダークラスを内包

2. **SearchQuery** (`app/services/search_query.rb`)
   - 既存のシンプル検索と高度な検索を統合
   - パラメータに応じて適切な検索方式を自動選択

3. **InventoriesController** (`app/controllers/inventories_controller.rb`)
   - 検索パラメータの受け取りと処理
   - ViewとServiceの橋渡し役

4. **検索UI** (`app/views/inventories/`)
   - シンプル検索と高度な検索の切り替え可能なインターフェース
   - 直感的な検索フォーム

## 機能詳細

### 基本的な検索機能

#### AND/OR条件の組み合わせ

```ruby
# AND条件
AdvancedSearchQuery.build
  .where(status: "active")
  .where("quantity > ?", 0)

# OR条件
AdvancedSearchQuery.build
  .where(name: "Product A")
  .or_where(name: "Product B")

# 複数OR条件の一括適用
AdvancedSearchQuery.build
  .where_any([
    { quantity: 0 },
    { status: "archived" },
    ["price > ?", 1000]
  ])
```

#### 複雑な条件の入れ子構造

```ruby
AdvancedSearchQuery.build
  .complex_where do
    and do
      where(status: "active")
      or do
        where("quantity < ?", 10)
        where("price > ?", 500)
      end
    end
  end
```

### 関連テーブルの検索

#### バッチ（ロット）検索

```ruby
AdvancedSearchQuery.build
  .with_batch_conditions do
    lot_code("LOT001")
    expires_before(30.days.from_now)
    quantity_greater_than(0)
  end
```

#### 在庫ログ検索

```ruby
AdvancedSearchQuery.build
  .with_inventory_log_conditions do
    action_type("increment")
    by_user(user_id)
    changed_after(1.week.ago)
  end
```

#### 出荷・入荷情報検索

```ruby
# 出荷情報
AdvancedSearchQuery.build
  .with_shipment_conditions do
    status("shipped")
    destination_like("東京")
    tracking_number("TRACK001")
  end

# 入荷情報
AdvancedSearchQuery.build
  .with_receipt_conditions do
    status("received")
    source_like("Supplier")
    cost_range(1000, 5000)
  end
```

#### ポリモーフィック関連（監査ログ）

```ruby
AdvancedSearchQuery.build
  .with_audit_conditions do
    action("update")
    changed_fields_include("quantity")
    by_user(admin_id)
  end
```

### 便利メソッド

| メソッド | 説明 | 使用例 |
|---------|------|--------|
| `search_keywords` | 複数フィールドでのキーワード検索 | `.search_keywords("Product", fields: [:name, :description])` |
| `between_dates` | 日付範囲での絞り込み | `.between_dates("created_at", from, to)` |
| `in_range` | 数値範囲での絞り込み | `.in_range("price", 100, 500)` |
| `expiring_soon` | 期限切れ間近の商品 | `.expiring_soon(30)` |
| `out_of_stock` | 在庫切れ商品 | `.out_of_stock` |
| `low_stock` | 低在庫商品 | `.low_stock(10)` |
| `recently_updated` | 最近更新された商品 | `.recently_updated(7)` |

## UIからの使用方法

### 1. シンプル検索

在庫一覧画面で以下の基本的な検索が可能：
- キーワード検索（商品名）
- ステータスフィルター
- 在庫切れ商品の表示

### 2. 高度な検索

「高度な検索」リンクをクリックすると、以下の詳細な検索オプションが利用可能：

#### 基本検索
- キーワード（商品名・説明）
- ステータス
- 在庫状態（すべて/在庫切れ/低在庫/在庫あり）

#### 価格範囲
- 最低価格
- 最高価格

#### 日付範囲
- 登録日の開始日
- 登録日の終了日

#### バッチ情報
- ロットコード
- 期限日（以前/以降）
- 期限切れ間近オプション

#### 出荷・入荷情報
- 出荷ステータス、配送先
- 入荷ステータス、仕入先

#### その他のオプション
- 最近更新された商品
- 低在庫閾値の設定

## 検索パラメータ一覧

### 基本パラメータ

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| `q` | string | キーワード検索 |
| `status` | string | ステータス（active/archived） |
| `stock_filter` | string | 在庫状態（out_of_stock/low_stock/in_stock） |
| `low_stock_threshold` | integer | 低在庫の閾値 |

### 範囲検索パラメータ

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| `min_price` | decimal | 最低価格 |
| `max_price` | decimal | 最高価格 |
| `created_from` | date | 作成日開始 |
| `created_to` | date | 作成日終了 |

### バッチ関連パラメータ

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| `lot_code` | string | ロットコード |
| `expires_before` | date | 期限日（以前） |
| `expires_after` | date | 期限日（以降） |
| `expiring_soon` | boolean | 期限切れ間近フラグ |
| `expiring_days` | integer | 期限切れまでの日数 |

### 出荷・入荷パラメータ

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| `shipment_status` | string | 出荷ステータス |
| `destination` | string | 配送先 |
| `receipt_status` | string | 入荷ステータス |
| `source` | string | 仕入先 |

### その他のパラメータ

| パラメータ | 型 | 説明 |
|-----------|-----|------|
| `recently_updated` | boolean | 最近更新フラグ |
| `updated_days` | integer | 更新からの日数 |
| `sort` | string | ソート項目 |
| `direction` | string | ソート方向（asc/desc） |
| `page` | integer | ページ番号 |
| `advanced_search` | boolean | 高度な検索モードフラグ |

## 実装例

### コントローラーでの使用

```ruby
class InventoriesController < ApplicationController
  def index
    @inventories = SearchQuery.call(search_params)
                              .includes(:batches)
                              .page(params[:page])
                              .decorate
  end

  private

  def search_params
    params.permit(
      :q, :status, :stock_filter, # ... その他のパラメータ
    )
  end
end
```

### カスタム検索の実装

```ruby
# 期限切れ間近で低在庫の商品を検索
def critical_items
  AdvancedSearchQuery.build
    .with_status("active")
    .low_stock(20)
    .expiring_soon(14)
    .order_by("batches.expires_on", :asc)
    .results
end

# 特定ユーザーの最近の活動を検索
def user_recent_activities(user_id)
  AdvancedSearchQuery.build
    .with_inventory_log_conditions do
      by_user(user_id)
      changed_after(7.days.ago)
    end
    .order_by("inventory_logs.created_at", :desc)
    .results
end
```

## パフォーマンス最適化

### インデックス推奨

以下のインデックスを追加することで検索パフォーマンスが向上します：

```ruby
# db/migrate/xxx_add_search_indexes.rb
class AddSearchIndexes < ActiveRecord::Migration[8.0]
  def change
    # 在庫テーブル
    add_index :inventories, :status
    add_index :inventories, :quantity
    add_index :inventories, [:status, :quantity]
    add_index :inventories, :updated_at
    
    # バッチテーブル
    add_index :batches, :lot_code
    add_index :batches, :expires_on
    add_index :batches, [:inventory_id, :expires_on]
    
    # ログテーブル
    add_index :inventory_logs, [:inventory_id, :created_at]
    add_index :inventory_logs, [:user_id, :created_at]
    
    # 出荷・入荷テーブル
    add_index :shipments, [:inventory_id, :status]
    add_index :receipts, [:inventory_id, :status]
  end
end
```

### N+1問題の回避

```ruby
# 関連データを事前読み込み
AdvancedSearchQuery.build
  .includes(:batches, :inventory_logs, :shipments, :receipts)
  .with_batch_conditions { ... }
  .results
```

## トラブルシューティング

### よくある問題と解決方法

1. **重複レコードが表示される**
   - 原因：JOINによる重複
   - 解決：`.distinct`メソッドを使用

2. **検索が遅い**
   - 原因：インデックス不足
   - 解決：上記の推奨インデックスを追加

3. **メモリ使用量が多い**
   - 原因：大量データの一括読み込み
   - 解決：ページネーションを使用

## 今後の拡張予定

1. **全文検索対応**
   - PostgreSQLの全文検索機能統合
   - Elasticsearchとの連携

2. **保存検索**
   - よく使う検索条件の保存
   - 検索履歴機能

3. **検索結果のエクスポート**
   - CSV/Excel形式でのダウンロード
   - レポート生成機能

4. **API対応**
   - RESTful APIでの検索エンドポイント
   - GraphQL対応

## まとめ

この高度な検索機能により、StockRxは複雑な在庫管理ニーズに対応できる柔軟な検索システムを提供します。Ransackに依存せず、独自実装により高いカスタマイズ性とパフォーマンスを実現しています。