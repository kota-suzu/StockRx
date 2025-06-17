# frozen_string_literal: true

module AdminControllers::InventoriesHelper
  # 在庫状態に応じた行のスタイルクラスを返す（Bootstrap 5版）
  # @param inventory [Inventory] 在庫オブジェクト
  # @return [String] CSSクラス（在庫切れ：table-danger、在庫不足：table-warning、正常：空文字）
  def inventory_row_class(inventory)
    if inventory.quantity <= 0
      "table-danger"
    elsif inventory.low_stock?
      "table-warning"
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

  # ソートアイコンを表示（Bootstrap 5版）
  # 現在のソート状態に応じたアイコンを表示
  # @param column [String] 列名
  # @return [ActiveSupport::SafeBuffer] HTMLアイコン
  def sort_icon_for(column)
    return "".html_safe unless params[:sort] == column

    if params[:direction] == "asc"
      tag.i(class: "fas fa-sort-up ms-1")
    else
      tag.i(class: "fas fa-sort-down ms-1")
    end
  end

  # CSVインポート用のサンプルフォーマットを返す
  # @return [String] CSVサンプル
  def csv_sample_format
    "name,quantity,price,status\nノートパソコン ThinkPad X1,15,128000,active\nワイヤレスマウス Logitech MX,50,7800,active\nモニター 27インチ 4K,25,45000,active"
  end

  # 拡張CSVサンプル（より多くの例を含む）
  # @return [String] 拡張CSVサンプル
  def csv_extended_sample_format
    <<~CSV
      name,quantity,price,status
      ノートパソコン ThinkPad X1,15,128000,active
      デスクトップPC Dell OptiPlex,8,89000,active
      モニター 27インチ 4K,25,45000,active
      ワイヤレスマウス Logitech MX,50,7800,active
      メカニカルキーボード,30,12000,active
      在庫切れ商品例,0,5000,active
      アーカイブ商品例,10,3000,archived
      高額商品例,2,250000,active
      小数点価格例,100,1499.99,active
      特殊文字商品「テスト」,75,2500,active
    CSV
  end

  # ロット状態に応じた行のスタイルクラスを返す（Bootstrap 5版）
  # @param batch [Batch] ロットオブジェクト
  # @return [String] CSSクラス（期限切れ：table-danger、期限間近：table-warning、正常：空文字）
  def batch_row_class(batch)
    if batch.expired?
      "table-danger"
    elsif batch.expiring_soon?
      "table-warning"
    else
      ""
    end
  end

  # ロット別在庫表示用のヘルパーメソッド
  # @param batch [Batch] ロットオブジェクト
  # @return [String] ロットの状態を日本語で表示
  def lot_status_display(batch)
    if batch.expired?
      "期限切れ"
    elsif batch.expiring_soon?
      "期限間近"
    else
      "正常"
    end
  end

  # ロットの在庫割合を計算
  # @param batch [Batch] ロットオブジェクト
  # @param total_quantity [Integer] 総在庫数
  # @return [Float] パーセンテージ
  def lot_quantity_percentage(batch, total_quantity)
    return 0 if total_quantity <= 0
    (batch.quantity.to_f / total_quantity * 100).round(1)
  end

  # ロット状態に応じたバッジクラスを返す
  # @param batch [Batch] ロットオブジェクト
  # @return [String] Bootstrapバッジクラス
  def lot_status_badge_class(batch)
    if batch.expired?
      "bg-danger"
    elsif batch.expiring_soon?
      "bg-warning"
    else
      "bg-success"
    end
  end

  # TODO: 以下の機能実装が必要
  # - ロットの一括操作機能（期限切れロットの一括削除など）
  # - 在庫アラート設定の表示・管理機能
  # - 在庫履歴の詳細表示機能
  # - エクスポート機能（PDF、Excel対応）
  # - 在庫予測・分析機能
end
