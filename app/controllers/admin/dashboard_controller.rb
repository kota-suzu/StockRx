# frozen_string_literal: true

module AdminNamespace
  # 管理者ダッシュボード画面用コントローラ
  class DashboardController < BaseController
    def index
      # 将来的には以下のようなサマリー情報を表示する予定
      # @inventory_low_stock = Inventory.low_stock.count
      # @orders_today = Order.created_today.count
      # @monthly_sales = Order.monthly_sales
    end
  end
end
