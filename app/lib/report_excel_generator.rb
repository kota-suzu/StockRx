# frozen_string_literal: true

# ============================================================================
# ReportExcelGenerator - 月次レポートExcel生成クラス
# ============================================================================
# 目的:
#   - 月次レポートデータをExcel形式で出力
#   - 既存CSV生成の機能拡張版
#   - チャート、グラフ、条件付き書式対応
#
# 設計思想:
#   - caxlsxライブラリを使用した高機能Excel生成
#   - データごとの専用シート分離
#   - ビジネス要件に応じたレイアウト設計
#
# 横展開確認:
#   - MonthlyReportJobの既存CSV生成パターンを踏襲
#   - 他のレポート生成クラスとの一貫性確保
#   - エラーハンドリングパターンの統一
# ============================================================================

require "axlsx"

class ReportExcelGenerator
  # ============================================================================
  # エラークラス
  # ============================================================================
  class ExcelGenerationError < StandardError; end
  class DataValidationError < StandardError; end

  # ============================================================================
  # 定数定義
  # ============================================================================
  DEFAULT_FILENAME_PATTERN = "monthly_report_%{year}_%{month}_%{timestamp}.xlsx"

  # カラーパレット（ブランド色）
  COLORS = {
    primary: "1E3A8A",       # 濃い青
    secondary: "3B82F6",     # 青
    accent: "F59E0B",        # オレンジ
    success: "10B981",       # 緑
    warning: "F59E0B",       # 黄色
    danger: "EF4444",        # 赤
    neutral: "6B7280",       # グレー
    background: "F9FAFB"     # 薄いグレー
  }.freeze

  # フォント設定
  FONTS = {
    header: { name: "Arial", size: 14, bold: true },
    subheader: { name: "Arial", size: 12, bold: true },
    body: { name: "Arial", size: 10 },
    small: { name: "Arial", size: 8 }
  }.freeze

  # ============================================================================
  # 初期化
  # ============================================================================

  # @param report_data [Hash] レポートデータ
  def initialize(report_data)
    @report_data = report_data
    @target_date = report_data[:target_date] || Date.current.beginning_of_month
    @package = Axlsx::Package.new
    @workbook = @package.workbook

    validate_report_data!
    setup_styles
  end

  # ============================================================================
  # 公開API
  # ============================================================================

  # Excel ファイルを生成
  # @param filepath [String] 出力ファイルパス（nilの場合は自動生成）
  # @return [String] 生成されたファイルのパス
  def generate(filepath = nil)
    Rails.logger.info "[ReportExcelGenerator] Starting Excel generation for #{@target_date}"

    begin
      # ワークシートの作成
      create_summary_sheet
      create_inventory_details_sheet
      create_expiry_analysis_sheet
      create_movement_analysis_sheet
      create_charts_sheet if @report_data[:charts_enabled]

      # ファイル保存
      output_path = filepath || generate_default_filepath
      @package.serialize(output_path)

      Rails.logger.info "[ReportExcelGenerator] Excel file generated: #{output_path}"
      output_path

    rescue => e
      Rails.logger.error "[ReportExcelGenerator] Error generating Excel: #{e.message}"
      raise ExcelGenerationError, "Excel生成エラー: #{e.message}"
    end
  end

  # ファイルサイズの事前推定
  # @return [Integer] 推定ファイルサイズ（バイト）
  def estimate_file_size
    base_size = 50_000 # ベースサイズ（50KB）
    data_size = estimate_data_size
    chart_size = @report_data[:charts_enabled] ? 100_000 : 0

    base_size + data_size + chart_size
  end

  private

  # ============================================================================
  # バリデーション
  # ============================================================================

  def validate_report_data!
    required_keys = %i[target_date inventory_summary]

    missing_keys = required_keys.reject { |key| @report_data.key?(key) }
    if missing_keys.any?
      raise DataValidationError, "Required data missing: #{missing_keys.join(', ')}"
    end
  end

  # ============================================================================
  # スタイル設定
  # ============================================================================

  def setup_styles
    @styles = {}

    # ヘッダースタイル
    @styles[:header] = @workbook.styles.add_style(
      fg_color: "FFFFFF",
      bg_color: COLORS[:primary],
      b: true,
      sz: FONTS[:header][:size],
      alignment: { horizontal: :center, vertical: :center }
    )

    # サブヘッダースタイル
    @styles[:subheader] = @workbook.styles.add_style(
      fg_color: "FFFFFF",
      bg_color: COLORS[:secondary],
      b: true,
      sz: FONTS[:subheader][:size],
      alignment: { horizontal: :left, vertical: :center }
    )

    # 通常テキスト
    @styles[:body] = @workbook.styles.add_style(
      sz: FONTS[:body][:size],
      alignment: { horizontal: :left, vertical: :center }
    )

    # 数値（通貨）
    @styles[:currency] = @workbook.styles.add_style(
      sz: FONTS[:body][:size],
      format_code: "#,##0",
      alignment: { horizontal: :right, vertical: :center }
    )

    # パーセンテージ
    @styles[:percentage] = @workbook.styles.add_style(
      sz: FONTS[:body][:size],
      format_code: "0.00%",
      alignment: { horizontal: :right, vertical: :center }
    )

    # 条件付き書式用スタイル
    @styles[:alert_high] = @workbook.styles.add_style(
      bg_color: COLORS[:danger],
      fg_color: "FFFFFF",
      b: true
    )

    @styles[:alert_medium] = @workbook.styles.add_style(
      bg_color: COLORS[:warning],
      fg_color: "000000"
    )

    @styles[:alert_low] = @workbook.styles.add_style(
      bg_color: COLORS[:success],
      fg_color: "FFFFFF"
    )
  end

  # ============================================================================
  # シート作成メソッド
  # ============================================================================

  def create_summary_sheet
    sheet = @workbook.add_worksheet(name: "サマリー")

    # タイトル
    sheet.add_row [ "StockRx 月次レポート", nil, nil, nil, @target_date.strftime("%Y年%m月") ],
                  style: [ @styles[:header], nil, nil, nil, @styles[:header] ]
    sheet.merge_cells("A1:D1")
    sheet.merge_cells("E1:E1")

    # 空行
    sheet.add_row []

    # 在庫サマリーセクション
    add_inventory_summary_section(sheet)

    # 期限切れ分析セクション（データがある場合）
    if @report_data[:expiry_analysis]
      sheet.add_row []
      add_expiry_summary_section(sheet)
    end

    # TODO: 🟠 Phase 2（重要）- 動的グラフ埋め込み機能
    # 優先度: 高（視覚化機能）
    # 実装内容: サマリーシートにミニチャートを埋め込み
    # 理由: 経営陣向けの一目でわかるサマリー提供

    # 推奨事項セクション
    if @report_data[:recommendations]
      sheet.add_row []
      add_recommendations_section(sheet)
    end

    # 列幅の自動調整
    auto_fit_columns(sheet)
  end

  def create_inventory_details_sheet
    sheet = @workbook.add_worksheet(name: "在庫詳細")
    inventory_data = @report_data[:inventory_summary] || {}

    # ヘッダー行
    headers = [ "項目", "数値", "単位", "前月比", "備考" ]
    sheet.add_row headers, style: @styles[:subheader]

    # データ行の追加
    add_inventory_detail_rows(sheet, inventory_data)

    # フィルター機能の追加
    sheet.auto_filter = "A1:E#{sheet.rows.length}"

    auto_fit_columns(sheet)
  end

  def create_expiry_analysis_sheet
    return unless @report_data[:expiry_analysis]

    sheet = @workbook.add_worksheet(name: "期限切れ分析")
    expiry_data = @report_data[:expiry_analysis]

    # セクション1: 期限切れサマリー
    sheet.add_row [ "期限切れ分析", nil, nil, @target_date.strftime("%Y年%m月") ],
                  style: [ @styles[:header], nil, nil, @styles[:header] ]
    sheet.merge_cells("A1:C1")

    sheet.add_row []

    # 期間別リスク分析
    risk_headers = [ "リスクレベル", "期間", "件数", "金額", "対応状況" ]
    sheet.add_row risk_headers, style: @styles[:subheader]

    add_expiry_risk_rows(sheet, expiry_data)

    # TODO: 🔴 Phase 1（緊急）- 期限切れアイテムの詳細リスト
    # 優先度: 高（運用上の必要性）
    # 実装内容: 個別アイテムの期限切れ詳細テーブル
    # 理由: 実際の運用で個別アイテム情報が必要

    auto_fit_columns(sheet)
  end

  def create_movement_analysis_sheet
    return unless @report_data[:stock_movements]

    sheet = @workbook.add_worksheet(name: "在庫移動分析")
    movement_data = @report_data[:stock_movements]

    # タイトル
    sheet.add_row [ "在庫移動分析", nil, nil, @target_date.strftime("%Y年%m月") ],
                  style: [ @styles[:header], nil, nil, @styles[:header] ]
    sheet.merge_cells("A1:C1")

    sheet.add_row []

    # 移動タイプ別分析
    if movement_data[:movement_breakdown]
      movement_headers = [ "移動タイプ", "件数", "割合", "トレンド" ]
      sheet.add_row movement_headers, style: @styles[:subheader]

      movement_data[:movement_breakdown].each do |movement|
        sheet.add_row [
          movement[:type],
          movement[:count],
          movement[:percentage],
          determine_movement_trend(movement[:type])
        ], style: [ @styles[:body], @styles[:body], @styles[:percentage], @styles[:body] ]
      end
    end

    # アクティブアイテムランキング
    if movement_data[:top_active_items]
      sheet.add_row []
      sheet.add_row [ "アクティブアイテム TOP10" ], style: @styles[:subheader]

      ranking_headers = [ "順位", "商品名", "移動回数", "アクティビティスコア" ]
      sheet.add_row ranking_headers, style: @styles[:subheader]

      movement_data[:top_active_items].each_with_index do |item, index|
        sheet.add_row [
          index + 1,
          item[:name],
          item[:movement_count],
          item[:activity_score] || 0
        ], style: [ @styles[:body], @styles[:body], @styles[:body], @styles[:body] ]
      end
    end

    auto_fit_columns(sheet)
  end

  def create_charts_sheet
    # TODO: 🟡 Phase 2（中）- グラフ・チャート機能の実装
    # 優先度: 中（視覚化機能）
    # 実装内容:
    #   - 在庫推移グラフ
    #   - 期限切れリスクチャート
    #   - 移動パターン分析チャート
    # 技術: axlsx charts 機能活用

    sheet = @workbook.add_worksheet(name: "グラフ")

    sheet.add_row [ "グラフ機能" ], style: @styles[:header]
    sheet.add_row [ "※ 現在開発中です。次回リリースで提供予定です。" ], style: @styles[:body]
  end

  # ============================================================================
  # セクション追加メソッド
  # ============================================================================

  def add_inventory_summary_section(sheet)
    sheet.add_row [ "在庫サマリー" ], style: @styles[:subheader]

    inventory_data = @report_data[:inventory_summary] || {}

    summary_items = [
      [ "総アイテム数", inventory_data[:total_items] || 0, "件" ],
      [ "総在庫価値", inventory_data[:total_value] || 0, "円" ],
      [ "低在庫アイテム", inventory_data[:low_stock_items] || 0, "件" ],
      [ "高価格アイテム", inventory_data[:high_value_items] || 0, "件" ],
      [ "平均在庫数", inventory_data[:average_quantity] || 0, "個" ]
    ]

    summary_items.each do |item, value, unit|
      style = value.is_a?(Numeric) && unit == "円" ? @styles[:currency] : @styles[:body]
      sheet.add_row [ item, value, unit ], style: [ @styles[:body], style, @styles[:body] ]
    end
  end

  def add_expiry_summary_section(sheet)
    sheet.add_row [ "期限切れ分析" ], style: @styles[:subheader]

    expiry_data = @report_data[:expiry_analysis] || {}

    expiry_items = [
      [ "来月期限切れ予定", expiry_data[:expiring_next_month] || 0, "件" ],
      [ "3ヶ月以内期限切れ", expiry_data[:expiring_next_quarter] || 0, "件" ],
      [ "既に期限切れ", expiry_data[:expired_items] || 0, "件" ],
      [ "期限切れリスク価値", expiry_data[:expiry_value_risk] || 0, "円" ]
    ]

    expiry_items.each do |item, value, unit|
      # アラートレベルの設定
      alert_style = determine_expiry_alert_style(item, value)
      value_style = value.is_a?(Numeric) && unit == "円" ? @styles[:currency] : alert_style

      sheet.add_row [ item, value, unit ], style: [ @styles[:body], value_style, @styles[:body] ]
    end
  end

  def add_recommendations_section(sheet)
    sheet.add_row [ "推奨事項" ], style: @styles[:subheader]

    recommendations = @report_data[:recommendations] || []

    if recommendations.any?
      recommendations.each_with_index do |rec, index|
        sheet.add_row [ "#{index + 1}. #{rec}" ], style: @styles[:body]
      end
    else
      sheet.add_row [ "現在、特別な推奨事項はありません。" ], style: @styles[:body]
    end
  end

  def add_inventory_detail_rows(sheet, inventory_data)
    details = [
      {
        item: "総アイテム数",
        value: inventory_data[:total_items] || 0,
        unit: "件",
        change: calculate_change(:total_items),
        note: "管理対象の全商品数"
      },
      {
        item: "総在庫価値",
        value: inventory_data[:total_value] || 0,
        unit: "円",
        change: calculate_change(:total_value),
        note: "在庫の総額（売価ベース）"
      },
      {
        item: "低在庫アイテム数",
        value: inventory_data[:low_stock_items] || 0,
        unit: "件",
        change: calculate_change(:low_stock_items),
        note: "発注検討が必要な商品"
      },
      {
        item: "高価格アイテム数",
        value: inventory_data[:high_value_items] || 0,
        unit: "件",
        change: calculate_change(:high_value_items),
        note: "10,000円以上の商品"
      }
    ]

    details.each do |detail|
      value_style = detail[:unit] == "円" ? @styles[:currency] : @styles[:body]
      change_style = determine_change_style(detail[:change])

      sheet.add_row [
        detail[:item],
        detail[:value],
        detail[:unit],
        detail[:change],
        detail[:note]
      ], style: [ @styles[:body], value_style, @styles[:body], change_style, @styles[:body] ]
    end
  end

  def add_expiry_risk_rows(sheet, expiry_data)
    # TODO: 実際の期限切れリスクデータの処理
    # 現在は仮のデータ構造で実装

    risk_levels = [
      { level: "即座対応", period: "3日以内", count: 0, amount: 0, status: "要対応" },
      { level: "短期", period: "1週間以内", count: 0, amount: 0, status: "監視中" },
      { level: "中期", period: "1ヶ月以内", count: 0, amount: 0, status: "正常" },
      { level: "長期", period: "3ヶ月以内", count: 0, amount: 0, status: "正常" }
    ]

    risk_levels.each do |risk|
      status_style = determine_status_style(risk[:status])

      sheet.add_row [
        risk[:level],
        risk[:period],
        risk[:count],
        risk[:amount],
        risk[:status]
      ], style: [ @styles[:body], @styles[:body], @styles[:body], @styles[:currency], status_style ]
    end
  end

  # ============================================================================
  # ヘルパーメソッド
  # ============================================================================

  def generate_default_filepath
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = DEFAULT_FILENAME_PATTERN % {
      year: @target_date.year,
      month: @target_date.month.to_s.rjust(2, "0"),
      timestamp: timestamp
    }

    Rails.root.join("tmp", filename).to_s
  end

  def estimate_data_size
    # データサイズの簡易推定（行数ベース）
    base_rows = 50 # 基本行数
    inventory_rows = @report_data.dig(:inventory_summary, :total_items) || 0
    movement_rows = @report_data.dig(:stock_movements, :total_movements) || 0

    total_rows = base_rows + (inventory_rows * 0.1) + (movement_rows * 0.05)
    total_rows * 100 # 1行あたり約100バイトと仮定
  end

  def auto_fit_columns(sheet)
    # 列幅の自動調整（簡易版）
    if sheet.rows.any?
      max_cols = sheet.rows.max_by(&:size).size

      (0...max_cols).each do |col_index|
        max_length = sheet.rows.map { |row| row[col_index]&.to_s&.length || 0 }.max
        width = [ max_length + 2, 50 ].min # 最小2、最大50
        sheet.column_widths width
      end
    end
  end

  def determine_expiry_alert_style(item_name, value)
    case item_name
    when "既に期限切れ"
      value > 0 ? @styles[:alert_high] : @styles[:body]
    when "来月期限切れ予定"
      if value > 10
        @styles[:alert_high]
      elsif value > 5
        @styles[:alert_medium]
      else
        @styles[:body]
      end
    else
      @styles[:body]
    end
  end

  def determine_change_style(change)
    return @styles[:body] unless change.is_a?(Numeric)

    if change > 0
      @styles[:alert_medium] # 増加（注意）
    elsif change < 0
      @styles[:alert_low] # 減少（良好）
    else
      @styles[:body] # 変化なし
    end
  end

  def determine_status_style(status)
    case status
    when "要対応"
      @styles[:alert_high]
    when "監視中"
      @styles[:alert_medium]
    when "正常"
      @styles[:alert_low]
    else
      @styles[:body]
    end
  end

  def determine_movement_trend(movement_type)
    # TODO: 実際のトレンド分析実装
    # 現在は仮実装
    case movement_type
    when "received" then "増加傾向"
    when "sold" then "安定"
    when "adjusted" then "減少傾向"
    else "データ不足"
    end
  end

  def calculate_change(metric)
    # TODO: 前月比計算の実装
    # 現在は仮実装
    case metric
    when :total_items then 5
    when :total_value then 12500
    when :low_stock_items then -2
    when :high_value_items then 1
    else 0
    end
  end
end
