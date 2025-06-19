module InventoryLogsHelper
  # 操作種別に応じたBootstrap 5バッジクラスを返す（レガシー対応）
  def operation_badge_class(operation_type)
    case operation_type.to_s
    when "add", "create"
      "badge bg-success bg-opacity-20 text-success"
    when "remove", "delete"
      "badge bg-danger bg-opacity-20 text-danger"
    when "adjust", "update"
      "badge bg-primary bg-opacity-20 text-primary"
    when "import"
      "badge bg-info bg-opacity-20 text-info"
    else
      "badge bg-secondary bg-opacity-20 text-secondary"
    end
  end

  # 操作種別に応じたBootstrap 5アイコンクラスを返す
  def operation_icon_class(operation_type)
    case operation_type.to_s
    when "add", "create"
      "bi-plus-circle-fill text-success"
    when "remove", "delete"
      "bi-trash3-fill text-danger"
    when "adjust", "update"
      "bi-pencil-square text-primary"
    when "import"
      "bi-cloud-download-fill text-info"
    else
      "bi-file-text-fill text-secondary"
    end
  end

  # 操作種別の日本語表示（拡張版）
  def operation_type_label(operation_type)
    case operation_type.to_s
    when "add", "create"
      "追加・新規登録"
    when "remove", "delete"
      "削除"
    when "adjust", "update"
      "調整・更新"
    when "import"
      "インポート"
    when "export"
      "エクスポート"
    when "transfer"
      "移動"
    when "count"
      "棚卸"
    else
      operation_type.to_s.humanize
    end
  end

  # 短縮版の操作種別表示
  def operation_type_short_label(operation_type)
    case operation_type.to_s
    when "add", "create"
      "追加"
    when "remove", "delete"
      "削除"
    when "adjust", "update"
      "更新"
    when "import"
      "インポート"
    else
      operation_type.to_s
    end
  end

  # 在庫ログのフィルタリングリンク生成（Bootstrap 5対応）
  def inventory_log_filter_links(current_filter = nil)
    filters = [
      { label: "全て", path: inventory_logs_path, key: nil, icon: "bi-list" },
      { label: "追加", path: inventory_logs_path(filter: "create"), key: "create", icon: "bi-plus-circle" },
      { label: "更新", path: inventory_logs_path(filter: "update"), key: "update", icon: "bi-pencil-square" },
      { label: "削除", path: inventory_logs_path(filter: "delete"), key: "delete", icon: "bi-trash" },
      { label: "インポート", path: inventory_logs_path(filter: "import"), key: "import", icon: "bi-download" }
    ]

    content_tag(:div, class: "btn-group mb-3", role: "group") do
      filters.map do |filter|
        active_class = filter[:key] == current_filter ? "active" : ""
        css_class = "btn btn-outline-primary btn-sm #{active_class}"

        link_to filter[:path], class: css_class do
          content_tag(:i, "", class: "#{filter[:icon]} me-1") + filter[:label]
        end
      end.join.html_safe
    end
  end

  # ログエントリの重要度に応じたクラス
  def log_importance_class(log)
    case log.operation_type.to_s
    when "delete"
      "border-start border-danger border-3"
    when "import"
      "border-start border-info border-3"
    when "create"
      "border-start border-success border-3"
    else
      ""
    end
  end

  # ログの詳細表示用
  def format_log_details(log)
    details = []

    if log.quantity_changed.present?
      details << "数量: #{log.quantity_changed}"
    end

    if log.note.present?
      details << "備考: #{truncate(log.note, length: 50)}"
    end

    if log.batch_id.present?
      details << "バッチ: #{log.batch_id}"
    end

    details.join(" | ")
  end

  # ログのタイムスタンプをフォーマット
  def format_log_timestamp(timestamp)
    return "不明" if timestamp.nil?

    if timestamp > 1.day.ago
      "#{time_ago_in_words(timestamp)}前"
    else
      l(timestamp, format: :short)
    end
  end

  # ユーザー表示（将来の多ユーザー対応用）
  def format_log_user(log)
    # 現在はadminのみだが、将来の拡張に備えて
    if log.respond_to?(:admin) && log.admin.present?
      log.admin.email
    elsif log.respond_to?(:user) && log.user.present?
      log.user.name || log.user.email
    else
      "システム"
    end
  end

  # ログ統計の表示
  def operation_count_badge(operation_type, count)
    return "" if count.zero?

    color_class = case operation_type.to_s
    when "create" then "success"
    when "update" then "primary"
    when "delete" then "danger"
    when "import" then "info"
    else "secondary"
    end

    content_tag(:span, count, class: "badge bg-#{color_class} ms-1")
  end

  # ログのグループ化ヘルパー
  def group_logs_by_date(logs)
    logs.group_by { |log| log.created_at.to_date }
        .sort_by { |date, _| date }
        .reverse
  end

  # 今日のログかどうか判定
  def today_log?(log)
    log.created_at.to_date == Date.current
  end

  # ログの期間フィルター
  def log_period_links(current_period = nil)
    periods = [
      { label: "今日", key: "today", path: inventory_logs_path(period: "today") },
      { label: "今週", key: "week", path: inventory_logs_path(period: "week") },
      { label: "今月", key: "month", path: inventory_logs_path(period: "month") },
      { label: "全期間", key: nil, path: inventory_logs_path }
    ]

    content_tag(:div, class: "btn-group btn-group-sm mb-3", role: "group") do
      periods.map do |period|
        active_class = period[:key] == current_period ? "active" : ""
        css_class = "btn btn-outline-secondary #{active_class}"

        link_to period[:label], period[:path], class: css_class
      end.join.html_safe
    end
  end
end
