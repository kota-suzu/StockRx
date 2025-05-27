module InventoryLogsHelper
  # 操作種別に応じたバッジクラスを返す
  def operation_badge_class(operation_type)
    case operation_type
    when "add"
      "px-2 py-1 rounded bg-green-100 text-green-800"
    when "remove"
      "px-2 py-1 rounded bg-red-100 text-red-800"
    when "adjust"
      "px-2 py-1 rounded bg-blue-100 text-blue-800"
    else
      "px-2 py-1 rounded bg-gray-100 text-gray-800"
    end
  end

  # 操作種別の日本語表示
  def operation_type_label(operation_type)
    case operation_type
    when "add"
      "追加"
    when "remove"
      "削除"
    when "adjust"
      "調整"
    else
      operation_type
    end
  end

  # 在庫ログのフィルタリングリンク生成
  def inventory_log_filter_links(current_filter = nil)
    filters = [
      { label: "全て", path: inventory_logs_path, key: nil },
      { label: "追加", path: operation_inventory_logs_path("add"), key: "add" },
      { label: "削除", path: operation_inventory_logs_path("remove"), key: "remove" },
      { label: "調整", path: operation_inventory_logs_path("adjust"), key: "adjust" }
    ]

    content_tag(:div, class: "flex space-x-2 mb-4") do
      filters.map do |filter|
        css_class = if filter[:key] == current_filter
                     "px-3 py-1 bg-blue-500 text-white rounded"
        else
                     "px-3 py-1 bg-gray-200 hover:bg-gray-300 text-gray-800 rounded"
        end

        link_to filter[:label], filter[:path], class: css_class
      end.join.html_safe
    end
  end
end
