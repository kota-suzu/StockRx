# frozen_string_literal: true

module AdminHelpers
  # 管理画面の在庫関連ヘルパーメソッド
  module InventoriesHelper
    # 在庫状態に応じた行のスタイルクラスを返す
    # @param inventory [Inventory] 在庫オブジェクト
    # @return [String] CSSクラス
    def inventory_row_class(inventory)
      if inventory.quantity <= 0
        "bg-red-50"
      elsif inventory.low_stock?
        "bg-yellow-50"
      else
        ""
      end
    end

    # ソート方向の切り替え
    # @param column [String] 列名
    # @return [String] ソート方向（"asc" or "desc"）
    def sort_direction_for(column)
      if params[:sort] == column && params[:direction] == "asc"
        "desc"
      else
        "asc"
      end
    end

    # ソートアイコンを表示
    # @param column [String] 列名
    # @return [SafeBuffer] HTMLアイコン
    def sort_icon_for(column)
      return "" unless params[:sort] == column

      if params[:direction] == "asc"
        tag.i(class: "fas fa-sort-up ml-1")
      else
        tag.i(class: "fas fa-sort-down ml-1")
      end
    end

    # CSVフォーマットのサンプルを返す
    # @return [String] CSVサンプル
    def csv_sample_format
      "name,quantity,price,status\n商品A,100,1000,active\n商品B,50,500,active"
    end
  end
end
