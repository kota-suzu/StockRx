module AdminControllers::DashboardHelper
  # 操作種別に応じたアイコンクラスを返す
  def operation_icon_class(operation_type)
    case operation_type.to_s
    when "create"
      "bi-plus-circle-fill"
    when "update"
      "bi-pencil-square"
    when "delete"
      "bi-trash3-fill"
    when "import"
      "bi-cloud-download-fill"
    else
      "bi-file-text-fill"
    end
  end

  # 操作種別に応じたBootstrapカラークラスを返す
  def operation_color_class(operation_type)
    case operation_type.to_s
    when "create"
      "success"
    when "update"
      "primary"
    when "delete"
      "danger"
    when "import"
      "info"
    else
      "secondary"
    end
  end

  # 操作種別の日本語表示
  def operation_type_label(operation_type)
    case operation_type.to_s
    when "create"
      "新規登録"
    when "update"
      "更新"
    when "delete"
      "削除"
    when "import"
      "インポート"
    else
      operation_type.to_s.humanize
    end
  end

  # システム状況のステータス表示
  def system_status_badge(status, label = nil)
    case status.to_s.downcase
    when "active", "running", "ok", "normal", "正常"
      badge_class = "bg-success bg-opacity-20 text-success"
      indicator_class = "bg-success"
      display_label = label || "正常"
    when "inactive", "stopped", "error", "エラー"
      badge_class = "bg-danger bg-opacity-20 text-danger"
      indicator_class = "bg-danger"
      display_label = label || "エラー"
    when "warning", "警告"
      badge_class = "bg-warning bg-opacity-20 text-warning"
      indicator_class = "bg-warning"
      display_label = label || "警告"
    when "pending", "planned", "実装予定"
      badge_class = "bg-info bg-opacity-20 text-info"
      indicator_class = "bg-info"
      display_label = label || "実装予定"
    else
      badge_class = "bg-secondary bg-opacity-20 text-secondary"
      indicator_class = "bg-secondary"
      display_label = label || "不明"
    end

    {
      badge_class: badge_class,
      indicator_class: indicator_class,
      label: display_label
    }
  end

  # サマリーカードのアイコンを返す
  def summary_icon_class(type)
    case type.to_s
    when "new_products", "products"
      "bi-plus-circle"
    when "updates", "inventory_updates"
      "bi-arrow-repeat"
    when "alerts", "warnings"
      "bi-exclamation-triangle"
    when "expired", "expiry"
      "bi-clock-history"
    when "total_value", "value"
      "bi-currency-yen"
    when "low_stock"
      "bi-box-seam"
    else
      "bi-info-circle"
    end
  end

  # サマリーカードの色クラスを返す
  def summary_color_class(type)
    case type.to_s
    when "new_products", "products"
      "primary"
    when "updates", "inventory_updates"
      "success"
    when "alerts", "warnings", "low_stock"
      "warning"
    when "expired", "expiry"
      "danger"
    when "total_value", "value"
      "info"
    else
      "secondary"
    end
  end

  # 数値をフォーマットして表示
  def format_dashboard_number(number)
    return "-" if number.nil? || number == 0

    if number >= 1_000_000
      "#{(number / 1_000_000.0).round(1)}M"
    elsif number >= 1_000
      "#{(number / 1_000.0).round(1)}K"
    else
      number_with_delimiter(number)
    end
  end

  # 金額をフォーマットして表示
  def format_dashboard_currency(amount)
    return "-" if amount.nil? || amount == 0

    if amount >= 1_000_000
      "¥#{(amount / 1_000_000.0).round(1)}M"
    elsif amount >= 1_000
      "¥#{(amount / 1_000.0).round(1)}K"
    else
      "¥#{number_with_delimiter(amount)}"
    end
  end

  # アラートレベルに応じたクラスを返す
  def alert_level_class(count, warning_threshold = 5, danger_threshold = 10)
    return "success" if count == 0
    return "warning" if count < warning_threshold
    return "danger" if count >= danger_threshold
    "info"
  end

  # 時間の表示をより読みやすく
  def format_relative_time(time)
    return "不明" if time.nil?

    distance = time_ago_in_words(time)
    case distance
    when /less than a minute/i, /1分未満/
      "たった今"
    when /\d+ minutes?/i
      distance.gsub(/minutes?/, "分") + "前"
    when /about an hour/i, /約1時間/
      "約1時間前"
    when /\d+ hours?/i
      distance.gsub(/hours?/, "時間") + "前"
    when /1 day/i, /1日/
      "昨日"
    when /\d+ days?/i
      distance.gsub(/days?/, "日") + "前"
    else
      distance + "前"
    end
  end

  # ツールチップ用のメッセージを生成
  def tooltip_message(action, item_name = nil)
    case action.to_s
    when "view_details"
      item_name ? "#{item_name}の詳細を表示" : "詳細を表示"
    when "edit"
      item_name ? "#{item_name}を編集" : "編集"
    when "delete"
      item_name ? "#{item_name}を削除" : "削除"
    when "add_new"
      item_name ? "新しい#{item_name}を追加" : "新規作成"
    when "view_all"
      item_name ? "すべての#{item_name}を表示" : "すべて表示"
    else
      action.to_s.humanize
    end
  end

  # ダッシュボード統計の計算ヘルパー
  def calculate_percentage_change(current, previous)
    return 0 if previous.nil? || previous == 0
    ((current - previous).to_f / previous * 100).round(1)
  end

  # 変化率に応じたクラスを返す
  def percentage_change_class(percentage)
    return "text-muted" if percentage == 0
    percentage > 0 ? "text-success" : "text-danger"
  end

  # 変化率のアイコンを返す
  def percentage_change_icon(percentage)
    return "bi-dash" if percentage == 0
    percentage > 0 ? "bi-arrow-up" : "bi-arrow-down"
  end
end
