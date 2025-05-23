# frozen_string_literal: true

module InventoryStatistics
  extend ActiveSupport::Concern

  included do
    scope :low_stock, -> (threshold = 5) { where("quantity <= ? AND quantity > 0", threshold) }
    scope :out_of_stock, -> { where("quantity <= 0") }
    scope :normal_stock, -> (threshold = 5) { where("quantity > ?", threshold) }
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
    [(expiry_date - Date.current).to_i, 0].max
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
  end
end
end
