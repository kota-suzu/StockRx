module InventoryStatistics
  extend ActiveSupport::Concern

  included do
    # Inventory モデル側でスコープが再定義されるため、ここではコメントアウトまたは削除を検討。
    # ユーザー指示のコード片にはスコープ定義がないため、既存のものを残し、
    # Inventory モデル側の定義が優先されることを期待します。
    # ただし、Inventory モデルの LOW_STOCK_THRESHOLD を参照するように変更します。
    scope :low_stock, ->(threshold = Inventory::LOW_STOCK_THRESHOLD) { where("quantity > 0 AND quantity <= ?", threshold) }
    scope :out_of_stock, -> { where("quantity <= 0") } # Inventoryモデルの定義に合わせる
    scope :normal_stock, ->(threshold = Inventory::LOW_STOCK_THRESHOLD) { where("quantity > ?", threshold) }
  end

  def low_stock?(threshold = nil)
    # Inventoryモデル側でオーバーライドされる想定
    threshold ||= respond_to?(:low_stock_threshold) ? low_stock_threshold : Inventory::LOW_STOCK_THRESHOLD
    quantity > 0 && quantity <= threshold
  end

  def out_of_stock?
    # Inventoryモデル側でオーバーライドされる想定
    quantity <= 0
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
    [ (expiry_date - Date.current).to_i, 0 ].max
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

  def stock_status(low_threshold = nil)
    # Inventoryモデルのメソッド(オーバーライドされたもの)が使われることを期待
    if self.out_of_stock?
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
        total_items:        count, # ユーザー指示のキー名に合わせる
        total_quantity:     sum(:quantity), # ユーザー指示のキー名に合わせる
        total_value:        sum("price * quantity"), # DB側で計算
        out_of_stock_count: out_of_stock.count, # self.out_of_stock を使用
        low_stock_count:    low_stock.count,    # self.low_stock を使用
        normal_stock_count: normal_stock.count  # self.normal_stock を使用
      }
    end

    def expiring_items(days = 30)
      if column_names.include?("expiry_date")
        where("expiry_date <= ?", Date.current + days.days)
          .where("quantity > 0")
          .order(:expiry_date)
      elsif column_names.include?("expires_on")
        where("expires_on <= ?", Date.current + days.days)
          .where("quantity > 0")
          .order(:expires_on)
      else
        none
      end
    end

    def alert_summary
      expiring_field = column_names.include?("expiry_date") ? "expiry_date" :
                       (column_names.include?("expires_on") ? "expires_on" : nil)

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
