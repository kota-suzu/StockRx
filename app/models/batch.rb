class Batch < ApplicationRecord
  include InventoryStatistics

  belongs_to :inventory, optional: false

  # バリデーション
  validates :lot_code, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  # ロットコードと在庫IDの組み合わせでユニーク（DBレベルでも制約あり）
  validates :lot_code, uniqueness: { scope: :inventory_id, case_sensitive: false }

  # スコープ
  scope :expired, -> { where("expires_on < ?", Date.current) }
  scope :not_expired, -> { where("expires_on >= ? OR expires_on IS NULL", Date.current) }
  scope :expiring_soon, ->(days = 30) { where("expires_on BETWEEN ? AND ?", Date.current, Date.current + days.days) }
  scope :out_of_stock, -> { where(quantity: 0) }
  scope :low_stock, ->(threshold = Inventory::LOW_STOCK_THRESHOLD) { where("quantity > 0 AND quantity <= ?", threshold) }
  scope :normal_stock, ->(threshold = 5) { where("quantity > ?", threshold) }

  # TODO: 期限切れアラート機能の実装
  # TODO: バッチ詳細表示機能の追加

  # TODO: 入荷登録機能の拡張
  # - 入荷日の記録と追跡
  # - サプライヤー情報の関連付け
  # - 入荷コストの記録

  # TODO: バッチ移動・譲渡機能
  # - 他の在庫への移動履歴
  # - 複数ロケーション管理

  # TODO: バッチ品質管理機能
  # - 品質検査結果の記録
  # - 温度管理要件の設定と監視
  # - バッチごとの安全性情報の記録

  # 期限切れかどうかを判定するメソッド（InventoryStatisticsでの実装を上書き）
  def expired?
    expires_on.present? && expires_on < Date.current
  end

  # 期限切れが近いかどうかを判定するメソッド（InventoryStatisticsでの実装を上書き）
  def expiring_soon?(days_threshold = 30)
    expires_on.present? && !expired? && expires_on <= Date.current + days_threshold.days
  end

  # 在庫が少ないかどうかを判定するメソッド
  def low_stock?(threshold = nil)
    threshold ||= low_stock_threshold
    quantity.positive? && quantity <= threshold
  end

  # 低在庫しきい値を取得するメソッド
  def low_stock_threshold
    Inventory::LOW_STOCK_THRESHOLD
  end
end
