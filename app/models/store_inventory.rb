# frozen_string_literal: true

class StoreInventory < ApplicationRecord
  # アソシエーション
  belongs_to :store, counter_cache: true
  belongs_to :inventory

  # 在庫移動ログ関連（Phase 2で実装予定）
  # has_many :transfer_logs, dependent: :destroy

  # ============================================
  # バリデーション
  # ============================================
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :reserved_quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :safety_stock_level, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :store_id, uniqueness: { scope: :inventory_id, message: "この店舗には既に同じ商品の在庫が登録されています" }

  # ビジネスロジックバリデーション
  validate :reserved_quantity_not_exceed_quantity
  validate :quantity_sufficient_for_reservation

  # ============================================
  # callbacks
  # ============================================
  before_update :update_last_updated_at, if: :quantity_changed?
  after_commit :check_stock_alerts, on: [ :create, :update ]
  after_commit :update_store_low_stock_count, on: [ :create, :update, :destroy ]

  # ============================================
  # スコープ
  # ============================================
  scope :available, -> { where("quantity > reserved_quantity") }
  scope :low_stock, -> { where("quantity <= safety_stock_level") }
  scope :critical_stock, -> { where("quantity <= safety_stock_level * 0.5") }
  scope :out_of_stock, -> { where(quantity: 0) }
  scope :overstocked, -> { where("quantity > safety_stock_level * 3") }
  scope :by_store, ->(store) { where(store: store) }
  scope :by_inventory, ->(inventory) { where(inventory: inventory) }

  # ============================================
  # インスタンスメソッド
  # ============================================

  # 利用可能在庫数（予約分を除く）
  def available_quantity
    quantity - reserved_quantity
  end

  # 在庫状態判定
  def stock_level_status
    return :out_of_stock if quantity.zero?
    return :critical if quantity <= (safety_stock_level * 0.5)
    return :low if quantity <= safety_stock_level
    return :optimal if quantity <= (safety_stock_level * 2)

    :excess
  end

  # 在庫状態の日本語表示
  def stock_level_status_text
    case stock_level_status
    when :out_of_stock then "在庫切れ"
    when :critical then "危険在庫"
    when :low then "低在庫"
    when :optimal then "適正在庫"
    when :excess then "過剰在庫"
    end
  end

  # 在庫値の計算
  def inventory_value
    quantity * inventory.price
  end

  # 予約済み在庫値の計算
  def reserved_value
    reserved_quantity * inventory.price
  end

  # 利用可能在庫値の計算
  def available_value
    available_quantity * inventory.price
  end

  # 在庫日数計算（簡易版）
  # TODO: Phase 3で売上データと連携した精密な計算を実装
  def days_of_stock_remaining(daily_usage_override = nil)
    usage = daily_usage_override || estimated_daily_usage
    return Float::INFINITY if usage.zero?

    available_quantity.to_f / usage
  end

  # 在庫補充が必要かどうか
  def needs_replenishment?
    quantity <= safety_stock_level
  end

  # 緊急補充が必要かどうか
  def needs_urgent_replenishment?
    quantity <= (safety_stock_level * 0.5)
  end

  # 移動可能な最大数量
  def max_transferable_quantity
    available_quantity
  end

  # ============================================
  # クラスメソッド
  # ============================================

  # 店舗の在庫サマリー
  def self.store_summary(store)
    store_items = where(store: store)

    {
      total_items: store_items.count,
      total_value: store_items.sum { |si| si.inventory_value },
      available_value: store_items.sum { |si| si.available_value },
      reserved_value: store_items.sum { |si| si.reserved_value },
      low_stock_count: store_items.low_stock.count,
      critical_stock_count: store_items.critical_stock.count,
      out_of_stock_count: store_items.out_of_stock.count,
      overstocked_count: store_items.overstocked.count
    }
  end

  # 商品の店舗別在庫状況
  def self.inventory_across_stores(inventory)
    includes(:store)
      .where(inventory: inventory)
      .map do |store_inventory|
        {
          store: store_inventory.store,
          quantity: store_inventory.quantity,
          available_quantity: store_inventory.available_quantity,
          reserved_quantity: store_inventory.reserved_quantity,
          stock_status: store_inventory.stock_level_status,
          last_updated: store_inventory.last_updated_at
        }
      end
  end

  # ============================================
  # TODO: Phase 2以降で実装予定の機能
  # ============================================
  # 1. 在庫移動履歴機能
  #    - 店舗間移動の詳細ログ
  #    - 在庫調整履歴の記録
  #    - 監査証跡の自動生成
  #
  # 2. 自動補充機能
  #    - 安全在庫を下回った際の自動アラート
  #    - 他店舗からの自動移動提案
  #    - 発注業者への自動発注提案
  #
  # 3. 在庫予測・分析機能
  #    - 売上データに基づく消費予測
  #    - 季節変動を考慮した在庫計画
  #    - ABC分析による重要度判定
  #
  # 4. リアルタイム在庫同期
  #    - ActionCableによるリアルタイム更新
  #    - 複数管理者間での同時編集制御
  #    - 在庫変更の即座通知

  private

  # 予約数量が総在庫数を超えないことを検証
  def reserved_quantity_not_exceed_quantity
    return unless reserved_quantity && quantity

    if reserved_quantity > quantity
      errors.add(:reserved_quantity, "は在庫数を超えることはできません")
    end
  end

  # 在庫数が予約に対して十分であることを検証
  def quantity_sufficient_for_reservation
    return unless quantity_changed? && reserved_quantity.present?
    return unless quantity.present?  # nilチェックを追加

    if quantity < reserved_quantity
      errors.add(:quantity, "は予約済み数量（#{reserved_quantity}）以上である必要があります")
    end
  end

  # 最終更新日時の自動設定
  def update_last_updated_at
    self.last_updated_at = Time.current
  end

  # 在庫アラートチェック（非同期処理）
  def check_stock_alerts
    # TODO: Phase 2でアラート機能実装時に詳細化
    # - メール通知
    # - 管理画面への通知バッジ
    # - Slackなどの外部サービス連携
    Rails.logger.info "在庫アラートチェック: #{store.name} - #{inventory.name} (数量: #{quantity})"
  end

  # 日次消費量の推定（簡易版）
  def estimated_daily_usage
    # TODO: Phase 3で実際の売上・消費データと連携
    # 現在は安全在庫レベルの10%をデフォルトとする
    [ safety_stock_level * 0.1, 1.0 ].max
  end

  # 店舗の低在庫アイテムカウントを更新
  def update_store_low_stock_count
    # 在庫数量か安全在庫レベルが変更された場合のみ更新
    return unless saved_change_to_quantity? || saved_change_to_safety_stock_level? || destroyed?
    
    store.update_low_stock_items_count! if store
  end
end
