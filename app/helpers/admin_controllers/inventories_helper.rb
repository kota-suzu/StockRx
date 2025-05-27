# frozen_string_literal: true

module AdminControllers::InventoriesHelper
  # 在庫状態に応じた行のスタイルクラスを返す
  # @param inventory [Inventory] 在庫オブジェクト
  # @return [String] CSSクラス（在庫切れ：bg-red-50、在庫不足：bg-yellow-50、正常：空文字）
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
  # 現在のソート状態に基づいて次のソート方向を決定する
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
  # 現在のソート状態に応じたアイコンを表示
  # @param column [String] 列名
  # @return [ActiveSupport::SafeBuffer] HTMLアイコン
  def sort_icon_for(column)
    return "".html_safe unless params[:sort] == column

    if params[:direction] == "asc"
      tag.i(class: "fas fa-sort-up ml-1")
    else
      tag.i(class: "fas fa-sort-down ml-1")
    end
  end

  # CSVインポート用のサンプルフォーマットを返す
  # @return [String] CSVサンプル
  def csv_sample_format
    "name,quantity,price,status\n商品A,100,1000,active\n商品B,50,500,active"
  end

  # バッチ状態に応じた行のスタイルクラスを返す
  # @param batch [Batch] バッチオブジェクト
  # @return [String] CSSクラス（期限切れ：bg-red-50、期限間近：bg-yellow-50、正常：空文字）
  def batch_row_class(batch)
    if batch.expired?
      "bg-red-50"
    elsif batch.expiring_soon?
      "bg-yellow-50"
    else
      ""
    end
  end

  # TODO: 以下の機能実装が必要
  # - バッチの一括操作機能（期限切れバッチの一括削除など）
  # - 在庫アラート設定の表示・管理機能
  # - 在庫履歴の詳細表示機能
  # - エクスポート機能（PDF、Excel対応）
  # - 在庫予測・分析機能
end
