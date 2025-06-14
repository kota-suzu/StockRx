# frozen_string_literal: true

# ============================================================================
# ReportPdfGenerator - 月次レポートPDF生成クラス
# ============================================================================
# 目的:
#   - 月次レポートサマリーをPDF形式で出力
#   - 経営陣向けのエグゼクティブサマリー生成
#   - 印刷・共有に適したレイアウト設計
#
# 設計思想:
#   - prawnライブラリを使用した高品質PDF生成
#   - A4サイズでの読みやすいレイアウト
#   - グラフィカルな要素とテーブルの組み合わせ
#
# 横展開確認:
#   - ReportExcelGeneratorとの一貫したデータ処理
#   - 同様のエラーハンドリングパターン
#   - カラーパレットとブランディングの統一
# ============================================================================

require "prawn"
require "prawn/table"

class ReportPdfGenerator
  include Prawn::View

  # ============================================================================
  # エラークラス
  # ============================================================================
  class PdfGenerationError < StandardError; end
  class DataValidationError < StandardError; end

  # ============================================================================
  # 定数定義
  # ============================================================================
  DEFAULT_FILENAME_PATTERN = "monthly_report_summary_%{year}_%{month}_%{timestamp}.pdf"

  # ページ設定
  PAGE_SIZE = "A4"
  PAGE_MARGIN = 40

  # カラーパレット（Excel生成と統一）
  COLORS = {
    primary: "1E3A8A",
    secondary: "3B82F6",
    accent: "F59E0B",
    success: "10B981",
    warning: "F59E0B",
    danger: "EF4444",
    neutral: "6B7280",
    background: "F9FAFB"
  }.freeze

  # フォント設定
  FONTS = {
    title: { size: 24, style: :bold },
    heading: { size: 16, style: :bold },
    subheading: { size: 12, style: :bold },
    body: { size: 10, style: :normal },
    small: { size: 8, style: :normal }
  }.freeze

  # ============================================================================
  # 初期化
  # ============================================================================

  # @param report_data [Hash] レポートデータ
  def initialize(report_data)
    @report_data = report_data
    # デフォルト値を事前に設定
    @report_data[:target_date] ||= Date.current.beginning_of_month
    @target_date = @report_data[:target_date]
    @document = Prawn::Document.new(
      page_size: PAGE_SIZE,
      margin: PAGE_MARGIN
    )

    validate_report_data!
    setup_fonts
  end

  # ============================================================================
  # 公開API
  # ============================================================================

  # PDF ファイルを生成
  # @param filepath [String] 出力ファイルパス（nilの場合は自動生成）
  # @return [String] 生成されたファイルのパス
  def generate(filepath = nil)
    Rails.logger.info "[ReportPdfGenerator] Starting PDF generation for #{@target_date}"

    begin
      # ページコンテンツの作成
      create_header
      create_executive_summary
      create_key_metrics
      create_risk_analysis
      create_recommendations
      create_footer

      # ファイル保存
      output_path = filepath || generate_default_filepath
      @document.render_file(output_path)

      Rails.logger.info "[ReportPdfGenerator] PDF file generated: #{output_path}"
      output_path

    rescue => e
      Rails.logger.error "[ReportPdfGenerator] Error generating PDF: #{e.message}"
      raise PdfGenerationError, "PDF生成エラー: #{e.message}"
    end
  end

  # ファイルサイズの事前推定
  # @return [Integer] 推定ファイルサイズ（バイト）
  def estimate_file_size
    base_size = 200_000 # ベースサイズ（200KB）
    content_size = estimate_content_size

    base_size + content_size
  end

  private

  # ============================================================================
  # バリデーション
  # ============================================================================

  def validate_report_data!
    required_keys = %i[target_date inventory_summary]

    missing_keys = required_keys.reject { |key| @report_data.key?(key) && @report_data[key] }
    if missing_keys.any?
      raise DataValidationError, "Required data missing: #{missing_keys.join(', ')}"
    end
  end

  # ============================================================================
  # 設定
  # ============================================================================

  def setup_fonts
    # UTF-8対応フォントの設定（日本語文字対応）
    begin
      # DejaVu SansはUTF-8をサポートしている
      font_path = Rails.root.join("vendor", "fonts", "DejaVuSans.ttf")
      if File.exist?(font_path)
        @document.font_families.update("DejaVuSans" => {
          normal: font_path.to_s
        })
        @document.font "DejaVuSans"
      else
        # フォールバック: ASCII文字のみ使用
        @document.font "Helvetica"
        Rails.logger.warn "[ReportPdfGenerator] UTF-8 font not found, using Helvetica (ASCII only)"
      end
    rescue => e
      @document.font "Helvetica"
      Rails.logger.warn "[ReportPdfGenerator] Font setup failed: #{e.message}, using Helvetica"
    end
  end

  # ============================================================================
  # レイアウト作成メソッド
  # ============================================================================

  def create_header
    @document.bounding_box([ 0, @document.cursor ], width: @document.bounds.width, height: 80) do
      # タイトル
      @document.font "Helvetica", style: :bold, size: FONTS[:title][:size] do
        @document.fill_color "1E3A8A"
        @document.text "StockRx Monthly Report", align: :center
      end

      @document.move_down 10

      # 期間とステータス
      @document.font "Helvetica", style: :normal, size: FONTS[:body][:size] do
        @document.fill_color "000000"

        period_text = "Period: #{@target_date.strftime('%Y/%m')}"
        generated_text = "Generated: #{Time.current.strftime('%Y/%m/%d %H:%M')}"

        @document.text_box period_text, at: [ 0, @document.cursor ], width: @document.bounds.width / 2
        @document.text_box generated_text, at: [ @document.bounds.width / 2, @document.cursor ],
                          width: @document.bounds.width / 2, align: :right
      end

      @document.move_down 15

      # 区切り線
      @document.stroke_color "CCCCCC"
      @document.stroke_horizontal_rule
      @document.stroke_color "000000"
    end

    @document.move_down 30
  end

  def create_executive_summary
    @document.font "Helvetica", style: :bold, size: FONTS[:heading][:size] do
      @document.fill_color "1E3A8A"
      @document.text "Executive Summary"
    end

    @document.move_down 10

    summary_text = generate_executive_summary_text

    @document.font "Helvetica", style: :normal, size: FONTS[:body][:size] do
      @document.fill_color "000000"
      @document.text summary_text, leading: 4
    end

    @document.move_down 20
  end

  def create_key_metrics
    @document.font "Helvetica", style: :bold, size: FONTS[:heading][:size] do
      @document.fill_color "1E3A8A"
      @document.text "Key Metrics"
    end

    @document.move_down 15

    # メトリクスを2列レイアウトで表示
    create_metrics_grid

    @document.move_down 20
  end

  def create_metrics_grid
    inventory_data = @report_data[:inventory_summary] || {}

    metrics = [
      {
        label: "Total Items",
        value: format_number(inventory_data[:total_items] || 0),
        unit: " items",
        change: calculate_change_indicator(:total_items),
        color: "3B82F6"
      },
      {
        label: "Total Value",
        value: format_currency(inventory_data[:total_value] || 0),
        unit: "",
        change: calculate_change_indicator(:total_value),
        color: "10B981"
      },
      {
        label: "Low Stock Items",
        value: format_number(inventory_data[:low_stock_items] || 0),
        unit: " items",
        change: calculate_change_indicator(:low_stock_items),
        color: determine_alert_color(inventory_data[:low_stock_items] || 0, 10)
      },
      {
        label: "Expiry Risk",
        value: format_currency(@report_data.dig(:expiry_analysis, :expiry_value_risk) || 0),
        unit: "",
        change: calculate_change_indicator(:expiry_risk),
        color: determine_alert_color(@report_data.dig(:expiry_analysis, :expired_items) || 0, 5)
      }
    ]

    # 2x2 グリッドでメトリクスを表示
    box_width = (@document.bounds.width - 20) / 2
    box_height = 60

    metrics.each_with_index do |metric, index|
      x = (index % 2) * (box_width + 20)
      y = @document.cursor - (index / 2) * (box_height + 10)

      create_metric_box(x, y, box_width, box_height, metric)
    end

    @document.move_down (metrics.length / 2) * (box_height + 10) + 10
  end

  def create_metric_box(x, y, width, height, metric)
    @document.bounding_box([ x, y ], width: width, height: height) do
      # 背景
      @document.fill_color "F9FAFB"
      @document.fill_rectangle [ 0, height ], width, height

      # ボーダー
      @document.stroke_color metric[:color]
      @document.line_width 2
      @document.stroke_rectangle [ 0, height ], width, height

      # ラベル
      @document.bounding_box([ 10, height - 10 ], width: width - 20, height: 20) do
        @document.font "Helvetica", style: :normal, size: FONTS[:small][:size] do
          @document.fill_color "6B7280"
          @document.text metric[:label], align: :left
        end
      end

      # 値
      @document.bounding_box([ 10, height - 25 ], width: width - 40, height: 25) do
        @document.font "Helvetica", style: :bold, size: FONTS[:subheading][:size] do
          @document.fill_color "000000"
          value_text = "#{metric[:value]}#{metric[:unit]}"
          @document.text value_text, align: :left
        end
      end

      # 変化指標
      if metric[:change]
        @document.bounding_box([ width - 35, height - 25 ], width: 30, height: 25) do
          @document.font "Helvetica", style: :normal, size: FONTS[:small][:size] do
            change_color = metric[:change][:direction] == "up" ? "EF4444" : "10B981"
            @document.fill_color change_color
            @document.text metric[:change][:symbol], align: :center, valign: :center
          end
        end
      end
    end
  end

  def create_risk_analysis
    return unless @report_data[:expiry_analysis]

    @document.font "Helvetica", style: :bold, size: FONTS[:heading][:size] do
      @document.fill_color "1E3A8A"
      @document.text "Risk Analysis"
    end

    @document.move_down 10

    # 期限切れリスクテーブル
    create_expiry_risk_table

    @document.move_down 20
  end

  def create_expiry_risk_table
    expiry_data = @report_data[:expiry_analysis] || {}

    table_data = [
      [ "Period", "Count", "Estimated Loss", "Risk Level" ]
    ]

    risk_items = [
      {
        period: "Immediate (within 3 days)",
        count: expiry_data[:expiring_immediate] || 0,
        amount: expiry_data[:immediate_value_risk] || 0,
        level: "High"
      },
      {
        period: "Short term (within 1 week)",
        count: expiry_data[:expiring_short_term] || 0,
        amount: expiry_data[:short_term_value_risk] || 0,
        level: "Medium"
      },
      {
        period: "Medium term (within 1 month)",
        count: expiry_data[:expiring_next_month] || 0,
        amount: expiry_data[:medium_term_value_risk] || 0,
        level: "Low"
      }
    ]

    risk_items.each do |item|
      table_data << [
        item[:period],
        format_number(item[:count]),
        format_currency(item[:amount]),
        item[:level]
      ]
    end

    @document.table(table_data,
      header: true,
      width: @document.bounds.width,
      cell_style: {
        size: FONTS[:body][:size],
        padding: [ 5, 8 ],
        border_width: 1,
        border_color: "CCCCCC"
      }
    ) do
      # ヘッダー行のスタイル
      row(0).style(
        background_color: "1E3A8A",
        text_color: "FFFFFF",
        font_style: :bold
      )

      # リスクレベル列の色分け
      column(-1).style do |cell|
        case cell.content
        when "High"
          cell.background_color = "FEE2E2"
          cell.text_color = "DC2626"
        when "Medium"
          cell.background_color = "FEF3C7"
          cell.text_color = "D97706"
        when "Low"
          cell.background_color = "DCFCE7"
          cell.text_color = "16A34A"
        end
      end
    end
  end

  def create_recommendations
    @document.font "Helvetica", style: :bold, size: FONTS[:heading][:size] do
      @document.fill_color "1E3A8A"
      @document.text "Recommendations"
    end

    @document.move_down 10

    recommendations = generate_recommendations_list

    recommendations.each_with_index do |rec, index|
      # 優先度アイコン
      priority_color = case rec[:priority]
      when "High" then "EF4444"
      when "Medium" then "F59E0B"
      when "Low" then "10B981"
      else "6B7280"
      end

      @document.bounding_box([ 0, @document.cursor ], width: @document.bounds.width) do
        # 優先度マーカー
        @document.fill_color priority_color
        @document.fill_rectangle [ 0, 15 ], 4, 15

        # 推奨事項テキスト
        @document.bounding_box([ 15, 15 ], width: @document.bounds.width - 15) do
          @document.font "Helvetica", style: :bold, size: FONTS[:body][:size] do
            @document.fill_color "000000"
            @document.text "#{index + 1}. #{rec[:title]}"
          end

          @document.move_down 3

          @document.font "Helvetica", style: :normal, size: FONTS[:body][:size] do
            @document.fill_color "4B5563"
            @document.text rec[:description], leading: 2
          end
        end
      end

      @document.move_down 15
    end
  end

  def create_footer
    @document.go_to_page(1) # 最初のページに戻る

    @document.bounding_box([ 0, 40 ], width: @document.bounds.width, height: 30) do
      # 区切り線
      @document.stroke_color "CCCCCC"
      @document.stroke_horizontal_rule
      @document.move_down 10

      # フッターテキスト
      @document.font "Helvetica", style: :normal, size: FONTS[:small][:size] do
        @document.fill_color "6B7280"

        footer_left = "StockRx Inventory Management System"
        footer_right = "Confidential - Handle with Care"

        @document.text_box footer_left, at: [ 0, @document.cursor ], width: @document.bounds.width / 2
        @document.text_box footer_right, at: [ @document.bounds.width / 2, @document.cursor ],
                          width: @document.bounds.width / 2, align: :right
      end
    end
  end

  # ============================================================================
  # コンテンツ生成メソッド
  # ============================================================================

  def generate_executive_summary_text
    inventory_data = @report_data[:inventory_summary] || {}
    expiry_data = @report_data[:expiry_analysis] || {}

    total_items = inventory_data[:total_items] || 0
    total_value = inventory_data[:total_value] || 0
    low_stock = inventory_data[:low_stock_items] || 0
    expired_items = expiry_data[:expired_items] || 0

    # TODO: 🟠 Phase 2（重要）- AIによる自動サマリー生成
    # 優先度: 高（付加価値向上）
    # 実装内容: データパターンからの自動的な洞察生成
    # 理由: 経営陣向けの高品質サマリー提供

    summary_parts = []

    summary_parts << "This report presents the inventory status for #{@target_date.strftime('%Y/%m')}."
    summary_parts << "Total inventory items: #{format_number(total_items)}, Total inventory value: #{format_currency(total_value)}."

    if low_stock > 0
      summary_parts << "#{format_number(low_stock)} items are in low stock status and require ordering consideration."
    end

    if expired_items > 0
      summary_parts << "#{format_number(expired_items)} expired items have been identified and require immediate attention."
    else
      summary_parts << "No expired items found, maintaining good inventory management."
    end

    summary_parts.join(" ")
  end

  def generate_recommendations_list
    recommendations = []

    inventory_data = @report_data[:inventory_summary] || {}
    expiry_data = @report_data[:expiry_analysis] || {}

    # 低在庫対応
    if (inventory_data[:low_stock_items] || 0) > 5
      recommendations << {
        priority: "High",
        title: "Consider ordering low stock items",
        description: "#{inventory_data[:low_stock_items]} items are in low stock status. Please review ordering plan to prevent stockouts."
      }
    end

    # 期限切れ対応
    if (expiry_data[:expired_items] || 0) > 0
      recommendations << {
        priority: "High",
        title: "Dispose of expired items",
        description: "#{expiry_data[:expired_items]} expired items have been identified. Please proceed with appropriate disposal procedures."
      }
    end

    # 予防的対策
    if (expiry_data[:expiring_next_month] || 0) > 10
      recommendations << {
        priority: "Medium",
        title: "Promote items nearing expiry",
        description: "#{expiry_data[:expiring_next_month]} items are scheduled to expire next month. Consider implementing promotional campaigns."
      }
    end

    # 在庫最適化
    if recommendations.empty?
      recommendations << {
        priority: "Low",
        title: "Continue efficient inventory management",
        description: "Current inventory status is good. Please continue maintaining efficient inventory management."
      }
    end

    recommendations
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

  def estimate_content_size
    # コンテンツサイズの簡易推定
    base_content = 100_000 # 基本コンテンツ（100KB）
    table_size = 50_000    # テーブル（50KB）

    base_content + table_size
  end

  def format_number(number)
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def format_currency(amount)
    "$#{format_number(amount)}"
  end

  def calculate_change_indicator(metric)
    # TODO: 実際の前月比計算実装
    # 現在は仮実装
    case metric
    when :total_items
      { direction: "up", symbol: "^", value: "+2.3%" }
    when :total_value
      { direction: "up", symbol: "^", value: "+5.1%" }
    when :low_stock_items
      { direction: "down", symbol: "v", value: "-1" }
    when :expiry_risk
      { direction: "down", symbol: "v", value: "-12%" }
    else
      nil
    end
  end

  def determine_alert_color(value, threshold)
    if value > threshold
      "EF4444" # 危険（赤）
    elsif value > threshold * 0.7
      "F59E0B" # 警告（黄）
    else
      "10B981" # 正常（緑）
    end
  end
end
