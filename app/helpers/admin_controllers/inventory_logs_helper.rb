# frozen_string_literal: true

module AdminControllers::InventoryLogsHelper
  # ============================================
  # 在庫ログ表示ヘルパーメソッド
  # CLAUDE.md準拠: 分析・レポート機能強化
  # ============================================

  # 在庫ログアクションのアイコンを返す
  # @param action [String] ログアクション（入荷、出荷、調整等）
  # @return [String] Bootstrap Iconクラス
  def inventory_log_action_icon(action)
    case action.to_s.downcase
    when "入荷", "receipt", "received"
      "bi bi-box-arrow-in-down text-success"
    when "出荷", "shipment", "shipped"
      "bi bi-box-arrow-up text-primary"
    when "調整", "adjustment", "adjusted"
      "bi bi-tools text-warning"
    when "移動", "transfer", "transferred"
      "bi bi-arrow-left-right text-info"
    when "廃棄", "disposal", "disposed"
      "bi bi-trash text-danger"
    when "棚卸", "stocktaking", "counted"
      "bi bi-clipboard-check text-secondary"
    when "期限切れ", "expired"
      "bi bi-calendar-x text-danger"
    when "返品", "return", "returned"
      "bi bi-arrow-return-left text-warning"
    else
      "bi bi-journal-text text-muted"
    end
  end

  # 在庫ログアクションの日本語表示名を返す
  # @param action [String] ログアクション
  # @return [String] 日本語表示名
  def inventory_log_action_name(action)
    case action.to_s.downcase
    when "receipt", "received"
      "入荷"
    when "shipment", "shipped"
      "出荷"
    when "adjustment", "adjusted"
      "調整"
    when "transfer", "transferred"
      "移動"
    when "disposal", "disposed"
      "廃棄"
    when "stocktaking", "counted"
      "棚卸"
    when "expired"
      "期限切れ"
    when "return", "returned"
      "返品"
    else
      action.humanize
    end
  end

  # 数量変化のバッジクラスを返す
  # @param quantity_change [Integer] 数量変化（正数：増加、負数：減少）
  # @return [String] Bootstrapバッジクラス
  def quantity_change_badge_class(quantity_change)
    return "badge bg-secondary" if quantity_change.zero?

    if quantity_change > 0
      "badge bg-success"
    else
      "badge bg-danger"
    end
  end

  # 数量変化の表示テキストを返す
  # @param quantity_change [Integer] 数量変化
  # @return [String] 表示テキスト（+50、-30等）
  def quantity_change_display(quantity_change)
    return "±0" if quantity_change.zero?

    if quantity_change > 0
      "+#{quantity_change}"
    else
      quantity_change.to_s
    end
  end

  # 在庫ログの重要度レベルを返す
  # @param log [InventoryLog] 在庫ログオブジェクト
  # @return [String] 重要度（high, medium, low）
  def inventory_log_importance_level(log)
    # 大量変動は高重要度
    return "high" if log.quantity_change.abs > 100

    # 負の変動（出荷・廃棄等）は中重要度
    return "medium" if log.quantity_change < 0

    # 通常の入荷は低重要度
    "low"
  end

  # 在庫ログの重要度バッジを返す
  # @param log [InventoryLog] 在庫ログオブジェクト
  # @return [String] HTMLバッジ
  def inventory_log_importance_badge(log)
    level = inventory_log_importance_level(log)

    case level
    when "high"
      content_tag(:span, "重要", class: "badge bg-danger ms-2")
    when "medium"
      content_tag(:span, "注意", class: "badge bg-warning text-dark ms-2")
    else
      ""
    end
  end

  # 在庫ログの時間差を人間に読みやすい形式で表示
  # @param log_time [DateTime] ログ時刻
  # @return [String] 相対時間表示（例：3時間前、2日前）
  def inventory_log_time_ago(log_time)
    return "不明" unless log_time

    time_ago_in_words(log_time, include_seconds: false) + "前"
  end

  # 在庫ログのフィルタリング用オプションを返す
  # @return [Array] セレクトボックス用オプション配列
  def inventory_log_action_options
    [
      [ "すべてのアクション", "" ],
      [ "入荷", "receipt" ],
      [ "出荷", "shipment" ],
      [ "調整", "adjustment" ],
      [ "移動", "transfer" ],
      [ "廃棄", "disposal" ],
      [ "棚卸", "stocktaking" ],
      [ "期限切れ", "expired" ],
      [ "返品", "return" ]
    ]
  end

  # 在庫ログの期間フィルタリング用オプションを返す
  # @return [Array] セレクトボックス用オプション配列
  def inventory_log_period_options
    [
      [ "すべての期間", "" ],
      [ "今日", "today" ],
      [ "昨日", "yesterday" ],
      [ "今週", "this_week" ],
      [ "先週", "last_week" ],
      [ "今月", "this_month" ],
      [ "先月", "last_month" ],
      [ "過去7日間", "7_days" ],
      [ "過去30日間", "30_days" ],
      [ "過去90日間", "90_days" ]
    ]
  end

  # 在庫ログの説明文を整形して返す
  # @param description [String] 説明文
  # @param max_length [Integer] 最大文字数（デフォルト：100文字）
  # @return [String] 整形された説明文
  def format_inventory_log_description(description, max_length = 100)
    return "説明なし" if description.blank?

    # HTMLタグを除去
    cleaned = strip_tags(description)

    # 長すぎる場合は省略
    if cleaned.length > max_length
      truncate(cleaned, length: max_length, omission: "...")
    else
      cleaned
    end
  end

  # 在庫ログのCSVエクスポート用ヘッダーを返す
  # @return [Array] CSVヘッダー配列
  def inventory_log_csv_headers
    [
      "日時",
      "商品名",
      "アクション",
      "数量変化",
      "変化後在庫",
      "実行者",
      "説明",
      "店舗",
      "ロット番号"
    ]
  end

  # 在庫ログの統計情報を計算
  # @param logs [ActiveRecord::Relation] 在庫ログのリレーション
  # @return [Hash] 統計情報ハッシュ
  def calculate_inventory_log_stats(logs)
    {
      total_logs: logs.count,
      receipts_count: logs.where(action: "receipt").count,
      shipments_count: logs.where(action: "shipment").count,
      adjustments_count: logs.where(action: "adjustment").count,
      total_quantity_in: logs.where("quantity_change > 0").sum(:quantity_change),
      total_quantity_out: logs.where("quantity_change < 0").sum(:quantity_change).abs,
      most_active_day: logs.group_by_day(:created_at).count.max_by { |_, count| count }&.first,
      recent_activity: logs.where(created_at: 24.hours.ago..Time.current).count
    }
  end

  # 在庫ログのサマリーカードを生成
  # @param stats [Hash] 統計情報
  # @return [String] HTMLサマリーカード
  def inventory_log_summary_cards(stats)
    content_tag(:div, class: "row g-3 mb-4") do
      [
        summary_card("総ログ数", stats[:total_logs], "bi-journal-text", "primary"),
        summary_card("入荷回数", stats[:receipts_count], "bi-box-arrow-in-down", "success"),
        summary_card("出荷回数", stats[:shipments_count], "bi-box-arrow-up", "info"),
        summary_card("調整回数", stats[:adjustments_count], "bi-tools", "warning")
      ].join.html_safe
    end
  end

  private

  # サマリーカードの個別生成
  # @param title [String] カードタイトル
  # @param value [Integer] 表示値
  # @param icon [String] Bootstrap Iconクラス
  # @param color [String] カラーテーマ
  # @return [String] HTMLカード
  def summary_card(title, value, icon, color)
    content_tag(:div, class: "col-md-3") do
      content_tag(:div, class: "card text-center border-#{color}") do
        content_tag(:div, class: "card-body") do
          content_tag(:div, class: "d-flex align-items-center justify-content-center mb-2") do
            content_tag(:i, "", class: "#{icon} me-2 text-#{color}") +
            content_tag(:h5, title, class: "card-title mb-0")
          end +
          content_tag(:h3, value || 0, class: "text-#{color}")
        end
      end
    end
  end
end

# ============================================
# TODO: Phase 3 - 分析・レポート機能の拡張
# ============================================
# 優先度: 中（機能強化）
#
# 【計画中の拡張機能】
# 1. 📊 高度な分析ヘルパー
#    - 在庫回転率計算
#    - 季節性分析
#    - トレンド分析
#    - 異常値検出
#
# 2. 📈 視覚化ヘルパー
#    - Chart.js用データ生成
#    - グラフ設定の自動化
#    - インタラクティブ要素
#
# 3. 📋 レポート生成ヘルパー
#    - 定型レポートテンプレート
#    - カスタムレポート機能
#    - 自動レポート配信
#
# 4. 🔔 アラート機能ヘルパー
#    - 閾値ベースアラート
#    - 予測ベースアラート
#    - 通知設定管理
# ============================================
