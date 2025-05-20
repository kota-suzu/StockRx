module InventoryStatistics
  extend ActiveSupport::Concern

  included do
    scope :low_stock, ->(threshold = 5) { where('quantity > 0 AND quantity <= ?', threshold) }
    scope :out_of_stock, -> { where(quantity: 0) }
    scope :normal_stock, ->(threshold = 5) { where('quantity > ?', threshold) }
  end

  def low_stock?(threshold = nil)
    threshold ||= low_stock_threshold if respond_to?(:low_stock_threshold)
    threshold ||= 5
    quantity > 0 && quantity <= threshold
  end

  def out_of_stock?
    quantity == 0
  end

  def expiring_soon?(days = 30)
    return false unless has_expiry_field? && expiry_date
    expiry_date <= Date.current + days.days && !expired?
  end

  def expired?
    has_expiry_field? && expiry_date && expiry_date < Date.current
  end

  def days_until_expiry
    return nil unless has_expiry_field? && expiry_date
    [(expiry_date - Date.current).to_i, 0].max
  end
  
  # 期限日フィールドがあるかどうか確認
  def has_expiry_field?
    respond_to?(:expiry_date) || respond_to?(:expires_on)
  end
  
  # 有効期限を取得する（対応するカラム名の違いを吸収）
  def expiry_date
    if respond_to?(:expires_on)
      expires_on
    elsif respond_to?(:expiry_date)
      self[:expiry_date]
    else
      nil
    end
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

  module ClassMethods
    def stock_summary
      {
        total_count: count,
        total_value: sum('quantity * price'),
        low_stock_count: low_stock.count,
        out_of_stock_count: out_of_stock.count,
        normal_stock_count: normal_stock.count
      }
    end

    def expiring_items(days = 30)
      if column_names.include?('expiry_date')
        where('expiry_date <= ?', Date.current + days.days)
          .where('quantity > 0')
          .order(:expiry_date)
      elsif column_names.include?('expires_on')
        where('expires_on <= ?', Date.current + days.days)
          .where('quantity > 0')
          .order(:expires_on)
      else
        none
      end
    end

    def alert_summary
      expiring_field = column_names.include?('expiry_date') ? 'expiry_date' : 
                       (column_names.include?('expires_on') ? 'expires_on' : nil)
      
      result = {
        low_stock: low_stock.pluck(:id, :name, :quantity),
        out_of_stock: out_of_stock.pluck(:id, :name, :quantity)
      }
      
      if expiring_field
        result[:expiring_soon] = expiring_items.pluck(:id, :name, expiring_field.to_sym)
      end
      
      result
    end
  end
end
