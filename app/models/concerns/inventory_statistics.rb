# frozen_string_literal: true

module InventoryStatistics
  extend ActiveSupport::Concern

  included do
    scope :low_stock, ->(threshold = 5) { where("quantity <= ? AND quantity > 0", threshold) }
    scope :out_of_stock, -> { where("quantity <= 0") }
    scope :normal_stock, ->(threshold = 5) { where("quantity > ?", threshold) }
    scope :active, -> { where(status: :active) }
    scope :search_by_name, ->(query) { where("name LIKE ?", "%#{query}%") }
    scope :search_by_code, ->(code) { where(code: code) }
  end

  # インスタンスメソッド
  def low_stock?(threshold = 5)
    quantity <= threshold && quantity > 0
  end

  def out_of_stock?
    quantity <= 0
  end

  def expiring_soon?(days = 30)
    return false unless respond_to?(:expiry_date) && expiry_date
    expiry_date <= Date.current + days.days
  end

  def days_until_expiry
    return nil unless respond_to?(:expiry_date) && expiry_date
    [ (expiry_date - Date.current).to_i, 0 ].max
  end

  def stock_status(low_threshold = 5)
    if out_of_stock?
      :out_of_stock
    elsif low_stock?(low_threshold)
      :low_stock
    else
      :normal
    end
  end

  # 在庫アラート閾値の設定（将来的には設定から取得するなど拡張予定）
  def low_stock_threshold
    5 # デフォルト値
  end

  # クラスメソッド
  module ClassMethods
    def stock_summary
      {
        total_count: count,
        total_value: sum("quantity * price"),
        low_stock_count: low_stock.count,
        out_of_stock_count: out_of_stock.count,
        normal_stock_count: normal_stock.count
      }
    end

    def expiring_items(days = 30)
      where("expiry_date <= ?", Date.current + days.days)
        .where("quantity > 0")
        .order(:expiry_date)
    end

    def alert_summary
      {
        low_stock: low_stock.pluck(:id, :name, :quantity),
        out_of_stock: out_of_stock.pluck(:id, :name, :quantity),
        expiring_soon: expiring_items.pluck(:id, :name, :expiry_date)
      }
    end

    # TODO: 在庫統計機能の拡張
    # 1. 動的閾値設定機能
    #    - 商品カテゴリ別の閾値設定
    #    - 販売履歴に基づく動的閾値計算
    #    - ユーザー定義可能な閾値設定画面
    #
    # 2. 高度な在庫分析機能
    #    - 在庫回転率の計算と可視化
    #    - ABC分析による商品分類
    #    - デッドストック検出機能
    #
    # 3. 予測機能
    #    - 機械学習による需要予測
    #    - 季節性を考慮した在庫計画
    #    - リードタイムを考慮した発注点計算
  end
end
