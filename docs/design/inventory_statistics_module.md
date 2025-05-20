# InventoryStatistics モジュール設計

在庫モデルで共通的に利用できる統計関連メソッドを `ActiveSupport::Concern` を使って整理しました。

## 目的

- 在庫数に関するスコープや判定メソッドを再利用可能にする
- モデル肥大化を防ぎ、関心事ごとにコードを分割する

## 提供機能

### スコープ
- `low_stock(threshold = 5)` : 在庫が閾値以下かつ0より大きいレコードを取得
- `out_of_stock` : 在庫が0以下のレコードを取得
- `normal_stock(threshold = 5)` : 在庫が閾値より多いレコードを取得

### インスタンスメソッド
- `low_stock?(threshold = 5)` : インスタンスが閾値以下か判定
- `out_of_stock?` : 在庫切れか判定
- `expiring_soon?(days = 30)` : `expiry_date` カラムを持つ場合に期限切れ間近か判定
- `days_until_expiry` : 期限までの日数を返す
- `stock_status(low_threshold = 5)` : `:low_stock`, `:out_of_stock`, `:normal` を返す

### クラスメソッド
- `stock_summary` : 件数や総在庫金額などの統計情報を返す
- `expiring_items(days = 30)` : 有効期限が近い在庫を取得
- `alert_summary` : アラート用の簡易統計を返す

## 利用方法

```ruby
class Inventory < ApplicationRecord
  include InventoryStatistics
  # ...
end
```

これにより在庫状態の判定や統計情報取得を複数モデルで共有できます。

## 今後の課題

- 期限切れ在庫の自動通知機能との連携
- 在庫レポート生成での統計利用範囲拡大
