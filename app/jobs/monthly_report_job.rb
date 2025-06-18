# frozen_string_literal: true

# ============================================
# Monthly Report Generation Job
# ============================================
# 月次レポート生成のバックグラウンド処理
# 大量データ処理・長時間実行ジョブの実装例
#
# TODO: 🔴 Phase 1（緊急）- ImportInventoriesJobのベストプラクティスを適用
#   推定期間: 2-3日
#   関連: docs/design/job_processing_design.md
#   横展開: ImportInventoriesJobと同等のセキュリティ・進捗管理パターン実装
# ============================================
# 1. セキュリティ強化
#    - ジョブ引数の検証追加（validate_job_arguments）
#    - 権限チェックの実装（管理者権限確認）
#    - データアクセス制限の実装
#
# 2. エラーハンドリングパターンの統一
#    - ImportInventoriesJobのhandle_success/handle_errorパターン適用
#    - 構造化されたエラー情報の記録
#    - リトライ時の状態管理改善
#
# 3. 進捗管理の高度化
#    - より詳細な進捗段階の定義
#    - 中間結果の保存機能
#    - 中断・再開機能の実装
#
# 4. パフォーマンス最適化
#    - バッチ処理の最適化（find_each使用）
#    - メモリ効率的なデータ処理
#    - クエリ最適化（N+1問題の解消）
#
# 5. 監視・メトリクス強化
#    - 処理時間の詳細記録
#    - メモリ使用量の監視
#    - レポート生成成功率の追跡

class MonthlyReportJob < ApplicationJob
  # ============================================
  # セキュリティ設定
  # ============================================
  # 月次レポートでの機密情報保護設定
  SENSITIVE_REPORT_PARAMS = %w[
    email_list recipient_data financial_data
    revenue_data cost_data profit_margin
    salary_info wage_data user_contacts
    admin_notifications recipient_emails
  ].freeze

  # 財務データ保護レベル
  FINANCIAL_PROTECTION_LEVEL = :strict  # :strict, :standard, :basic

  # ============================================
  # ProgressNotifier モジュールを include
  # ============================================
  include ProgressNotifier

  # ============================================
  # Sidekiq Configuration
  # ============================================
  queue_as :reports

  # Sidekiq specific options（レポート生成は時間がかかるためタイムアウト延長）
  sidekiq_options retry: 1, backtrace: true, queue: :reports, timeout: 600

  # @param target_date [Date] レポート対象月（デフォルトは先月）
  # @param admin_id [Integer] レポート要求者の管理者ID
  # @param report_types [Array<String>] 生成するレポートタイプ
  # @param output_formats [Array<String>] 出力形式（csv, pdf, excel）
  # @param enable_email [Boolean] メール通知を有効にするか（デフォルト：true）
  def perform(target_date = nil, admin_id = nil, report_types = %w[inventory_summary expiry_analysis], output_formats = %w[csv pdf excel], enable_email = true)
    target_date ||= Date.current.last_month.beginning_of_month

    # ジョブIDの生成と進捗追跡の初期化
    job_id = respond_to?(:jid) ? jid : SecureRandom.uuid
    status_key = nil

    if admin_id.present?
      status_key = initialize_progress(admin_id, job_id, "monthly_report", {
        target_date: target_date.iso8601,
        report_types: report_types,
        email_enabled: enable_email
      })
    end

    Rails.logger.info({
      event: "monthly_report_started",
      job_id: job_id,
      target_date: target_date.iso8601,
      admin_id: admin_id,
      report_types: report_types,
      email_enabled: enable_email
    }.to_json)

    report_data = {}

    begin
      # 進捗: データ収集開始 (10%)
      if status_key && admin_id
        update_progress(status_key, admin_id, "monthly_report", 10, "レポートタイプ分析中...")
      end

      # 各レポートタイプを新しいサービスクラスで生成
      total_reports = report_types.size
      report_types.each_with_index do |report_type, index|
        # 進捗計算: 10% + (現在のインデックス / 総数) * 40%
        progress = 10 + ((index.to_f / total_reports) * 40).to_i

        if status_key && admin_id
          update_progress(status_key, admin_id, "monthly_report", progress, "#{report_type}レポート生成中...")
        end

        case report_type
        when "inventory_summary"
          report_data[:inventory_summary] = InventoryReportService.monthly_summary(target_date)
        when "expiry_analysis"
          report_data[:expiry_analysis] = ExpiryAnalysisService.monthly_report(target_date)
        when "sales_summary"
          report_data[:sales_summary] = generate_sales_summary(target_date)
        when "performance_metrics"
          report_data[:performance_metrics] = generate_performance_metrics(target_date)
        else
          Rails.logger.warn "Unknown report type: #{report_type}"
        end
      end

      # 統合レポートデータの準備
      integrated_report_data = {
        target_date: target_date,
        inventory_summary: report_data[:inventory_summary],
        expiry_analysis: report_data.dig(:expiry_analysis, :expiry_summary),
        recommendations: generate_integrated_recommendations(report_data)
      }

      # 進捗: ファイル生成開始 (60%)
      if status_key && admin_id
        update_progress(status_key, admin_id, "monthly_report", 60, "レポートファイル生成中...")
      end

      # 複数形式でのファイル生成
      generated_files = generate_report_files(target_date, integrated_report_data, output_formats, status_key, admin_id)

      # 進捗: 通知処理 (90%)
      if status_key && admin_id
        update_progress(status_key, admin_id, "monthly_report", 90, "通知処理中...")
      end

      # 管理者への通知
      if admin_id.present?
        notify_report_completion(admin_id, target_date, generated_files, report_data, enable_email)
      else
        # 全管理者に通知（定期実行の場合）
        notify_all_admins(target_date, generated_files, report_data, enable_email)
      end

      # 進捗完了通知
      if status_key && admin_id
        notify_completion(status_key, admin_id, "monthly_report", {
          target_date: target_date.iso8601,
          generated_files: generated_files.map { |f| File.basename(f) },
          total_file_size: generated_files.sum { |f| File.size(f) },
          report_types: report_types,
          output_formats: output_formats
        })
      end

      # 結果をログに記録
      Rails.logger.info({
        event: "monthly_report_completed",
        job_id: job_id,
        target_date: target_date.iso8601,
        report_types: report_types,
        output_formats: output_formats,
        generated_files: generated_files,
        admin_id: admin_id,
        email_sent: enable_email,
        total_file_size_bytes: generated_files.sum { |f| File.size(f) }
      }.to_json)

      {
        status: "success",
        target_date: target_date,
        generated_files: generated_files,
        report_data: report_data
      }

    rescue => e
      # エラー通知
      if status_key && admin_id
        retry_count = respond_to?(:executions) ? executions : 0
        notify_error(status_key, admin_id, "monthly_report", e, retry_count)
      end

      Rails.logger.error({
        event: "monthly_report_failed",
        job_id: job_id,
        error_class: e.class.name,
        error_message: e.message,
        target_date: target_date.iso8601,
        admin_id: admin_id
      }.to_json)

      # エラー時は管理者に通知
      notify_report_error(admin_id, target_date, e) if admin_id.present?
      raise e
    end
  end

  private

  # ============================================
  # 新機能統合メソッド - Phase 1実装
  # ============================================

  def generate_report_files(target_date, report_data, output_formats, status_key = nil, admin_id = nil)
    generated_files = []
    total_formats = output_formats.size

    output_formats.each_with_index do |format, index|
      # 進捗計算: 60% + (現在のフォーマット / 総数) * 25%
      progress = 60 + ((index.to_f / total_formats) * 25).to_i

      if status_key && admin_id
        update_progress(status_key, admin_id, "monthly_report", progress, "#{format.upcase}ファイル生成中...")
      end

      begin
        case format.downcase
        when "csv"
          file_path = generate_csv_report(target_date, report_data)
          generated_files << file_path
          Rails.logger.info "[MonthlyReportJob] CSV file generated: #{file_path}"

        when "pdf"
          pdf_generator = ReportPdfGenerator.new(report_data)
          file_path = pdf_generator.generate
          generated_files << file_path
          Rails.logger.info "[MonthlyReportJob] PDF file generated: #{file_path}"

        when "excel"
          excel_generator = ReportExcelGenerator.new(report_data)
          file_path = excel_generator.generate
          generated_files << file_path
          Rails.logger.info "[MonthlyReportJob] Excel file generated: #{file_path}"

        else
          Rails.logger.warn "[MonthlyReportJob] Unknown output format: #{format}"
        end

      rescue => e
        Rails.logger.error "[MonthlyReportJob] Failed to generate #{format} file: #{e.message}"
        # 一つのフォーマット生成失敗でも他のフォーマットは継続
        next
      end
    end

    # 最低でも1つのファイルが生成されていることを確認
    if generated_files.empty?
      Rails.logger.warn "[MonthlyReportJob] No files were generated, creating fallback CSV"
      generated_files << generate_csv_report(target_date, report_data)
    end

    generated_files
  end

  def generate_integrated_recommendations(report_data)
    recommendations = []

    # 在庫サマリーベースの推奨事項
    if inventory_data = report_data[:inventory_summary]
      if (inventory_data[:low_stock_items] || 0) > 0
        recommendations << "低在庫アイテム（#{inventory_data[:low_stock_items]}件）の発注検討が必要です。"
      end

      if (inventory_data[:total_value] || 0) > 0
        value_per_item = inventory_data[:total_value].to_f / inventory_data[:total_items]
        if value_per_item > 5000
          recommendations << "高価値在庫が多いため、セキュリティ管理の強化を検討してください。"
        end
      end
    end

    # 期限切れ分析ベースの推奨事項
    if expiry_data = report_data.dig(:expiry_analysis, :expiry_summary)
      if (expiry_data[:expired_items] || 0) > 0
        recommendations << "期限切れアイテム（#{expiry_data[:expired_items]}件）の処分が必要です。"
      end

      if (expiry_data[:expiring_soon] || 0) > 5
        recommendations << "3日以内期限切れアイテム（#{expiry_data[:expiring_soon]}件）の緊急対応が必要です。"
      end
    end

    # デフォルト推奨事項
    if recommendations.empty?
      recommendations << "現在の在庫状況は良好です。継続的な管理を維持してください。"
    end

    recommendations
  end

  # ============================================
  # 既存メソッド（互換性維持）
  # ============================================

  def generate_inventory_summary(target_date)
    end_of_month = target_date.end_of_month

    {
      total_items: Inventory.count,
      total_value: Inventory.sum("quantity * price"),
      low_stock_items: Inventory.joins(:batches).where("batches.quantity <= 10").count,
      high_value_items: Inventory.where("price >= 10000").count,
      average_quantity: Inventory.average(:quantity)&.round(2),
      categories_breakdown: inventory_by_categories
    }
  end

  def generate_sales_summary(target_date)
    # 将来的にSalesモデルができた際の実装例
    {
      total_sales: 0, # Sales.where(created_at: target_date..target_date.end_of_month).sum(:total)
      orders_count: 0, # Sales.where(created_at: target_date..target_date.end_of_month).count
      average_order_value: 0, # 平均注文金額
      top_selling_items: [], # 売上上位商品
      monthly_trend: [] # 月間トレンド
    }
  end

  def generate_expiry_analysis(target_date)
    end_date = target_date + 1.month

    {
      expiring_next_month: expiring_items_count(30),
      expiring_next_quarter: expiring_items_count(90),
      expired_items: expired_items_count,
      expiry_value_risk: calculate_expiry_value_risk,
      recommended_actions: generate_expiry_recommendations
    }
  end

  def generate_performance_metrics(target_date)
    {
      inventory_turnover: calculate_inventory_turnover,
      stock_accuracy: calculate_stock_accuracy,
      fulfillment_rate: calculate_fulfillment_rate,
      carrying_cost: calculate_carrying_cost,
      stockout_incidents: count_stockout_incidents(target_date)
    }
  end

  def generate_csv_report(target_date, report_data)
    require "csv"

    filename = "monthly_report_#{target_date.strftime('%Y_%m')}_#{Time.current.to_i}.csv"
    file_path = Rails.root.join("tmp", filename)

    CSV.open(file_path, "w") do |csv|
      # ヘッダー
      csv << [ "\u30EC\u30DD\u30FC\u30C8\u9805\u76EE", "\u5024", "\u5099\u8003" ]

      # 在庫サマリー
      if report_data[:inventory_summary]
        data = report_data[:inventory_summary]
        csv << [ "=== \u5728\u5EAB\u30B5\u30DE\u30EA\u30FC ===", "", "" ]
        csv << [ "\u7DCF\u30A2\u30A4\u30C6\u30E0\u6570", data[:total_items], "\u4EF6" ]
        csv << [ "\u7DCF\u5728\u5EAB\u4FA1\u5024", data[:total_value], "\u5186" ]
        csv << [ "\u4F4E\u5728\u5EAB\u30A2\u30A4\u30C6\u30E0\u6570", data[:low_stock_items], "\u4EF6\uFF08\u95BE\u502410\u4EE5\u4E0B\uFF09" ]
        csv << [ "\u9AD8\u4FA1\u683C\u30A2\u30A4\u30C6\u30E0\u6570", data[:high_value_items], "\u4EF6\uFF0810,000\u5186\u4EE5\u4E0A\uFF09" ]
        csv << [ "\u5E73\u5747\u5728\u5EAB\u6570", data[:average_quantity], "\u500B" ]
        csv << [ "", "", "" ]
      end

      # 期限分析
      if report_data[:expiry_analysis]
        data = report_data[:expiry_analysis]
        csv << [ "=== \u671F\u9650\u5206\u6790 ===", "", "" ]
        csv << [ "\u6765\u6708\u671F\u9650\u5207\u308C\u4E88\u5B9A", data[:expiring_next_month], "\u4EF6" ]
        csv << [ "3\u30F6\u6708\u4EE5\u5185\u671F\u9650\u5207\u308C", data[:expiring_next_quarter], "\u4EF6" ]
        csv << [ "\u65E2\u306B\u671F\u9650\u5207\u308C", data[:expired_items], "\u4EF6" ]
        csv << [ "\u671F\u9650\u5207\u308C\u30EA\u30B9\u30AF\u4FA1\u5024", data[:expiry_value_risk], "\u5186" ]
        csv << [ "", "", "" ]
      end
    end

    file_path.to_s
  end

  def notify_report_completion(admin_id, target_date, generated_files, report_data, enable_email = true)
    admin = Admin.find_by(id: admin_id)
    return unless admin

    begin
      # ActionCable経由でリアルタイム通知
      ActionCable.server.broadcast("admin_#{admin_id}", {
        type: "monthly_report_complete",
        message: "月次レポート生成完了: #{target_date.strftime('%Y年%m月')}",
        generated_files: generated_files.map { |f| File.basename(f) },
        file_count: generated_files.size,
        summary: format_report_summary(report_data),
        timestamp: Time.current.iso8601
      })

      # メール通知（有効な場合のみ）
      if enable_email
        # 主要ファイル（PDF優先、次にExcel、最後にCSV）を添付
        primary_file = select_primary_file(generated_files)
        AdminMailer.monthly_report_complete(admin, primary_file, report_data.merge(
          target_date: target_date,
          generated_files: generated_files,
          file_count: generated_files.size
        )).deliver_now
        Rails.logger.info "Monthly report email sent to admin #{admin_id} with #{generated_files.size} files"
      end

    rescue => e
      Rails.logger.error "Failed to notify admin #{admin_id} about report completion: #{e.message}"
    end
  end

  def notify_all_admins(target_date, generated_files, report_data, enable_email = true)
    Admin.find_each do |admin|
      notify_report_completion(admin.id, target_date, generated_files, report_data, enable_email)
    end
  end

  def select_primary_file(generated_files)
    # PDF > Excel > CSV の優先順位でプライマリファイルを選択
    priority_order = [ ".pdf", ".xlsx", ".csv" ]

    priority_order.each do |extension|
      selected_file = generated_files.find { |file| file.end_with?(extension) }
      return selected_file if selected_file
    end

    # フォールバック: 最初のファイル
    generated_files.first
  end

  def notify_report_error(admin_id, target_date, error)
    admin = Admin.find_by(id: admin_id)
    return unless admin

    begin
      # ActionCable経由でエラー通知
      ActionCable.server.broadcast("admin_#{admin_id}", {
        type: "monthly_report_error",
        message: "月次レポート生成でエラーが発生しました: #{target_date.strftime('%Y年%m月')}",
        error_class: error.class.name,
        error_message: error.message,
        timestamp: Time.current.iso8601
      })

      # システムエラー通知メール
      AdminMailer.system_error_alert(admin, {
        error_class: error.class.name,
        error_message: error.message,
        occurred_at: Time.current,
        context: "Monthly Report Generation",
        target_date: target_date
      }).deliver_now

    rescue => e
      Rails.logger.error "Failed to notify admin #{admin_id} about report error: #{e.message}"
    end
  end

  def format_report_summary(report_data)
    {
      total_items: report_data.dig(:inventory_summary, :total_items),
      total_value: report_data.dig(:inventory_summary, :total_value),
      low_stock_items: report_data.dig(:inventory_summary, :low_stock_items),
      expiring_items: report_data.dig(:expiry_analysis, :expiring_next_month),
      performance_score: calculate_overall_performance_score(report_data)
    }
  end

  def calculate_overall_performance_score(report_data)
    # 総合パフォーマンススコア計算（100点満点）
    scores = []

    # 在庫効率スコア（50点）
    if inventory_data = report_data[:inventory_summary]
      low_stock_ratio = inventory_data[:low_stock_items].to_f / inventory_data[:total_items]
      inventory_score = [ 50 - (low_stock_ratio * 50), 0 ].max
      scores << inventory_score
    end

    # 期限管理スコア（30点）
    if expiry_data = report_data[:expiry_analysis]
      total_items = report_data.dig(:inventory_summary, :total_items) || 1
      expiry_ratio = expiry_data[:expired_items].to_f / total_items
      expiry_score = [ 30 - (expiry_ratio * 30), 0 ].max
      scores << expiry_score
    end

    # パフォーマンススコア（20点）
    if performance_data = report_data[:performance_metrics]
      perf_score = [
        performance_data[:stock_accuracy].to_f * 0.1,
        performance_data[:fulfillment_rate].to_f * 0.1
      ].sum
      scores << perf_score
    end

    scores.sum.round(1)
  end

  # ヘルパーメソッド
  def inventory_by_categories
    # 将来的にCategoryモデルができた際の実装
    { "\u305D\u306E\u4ED6" => Inventory.count }
  end

  def expiring_items_count(days)
    Inventory.joins(:batches)
             .where("batches.expires_on <= ? AND batches.expires_on > ?",
                    Date.current + days.days, Date.current)
             .distinct.count
  end

  def expired_items_count
    Inventory.joins(:batches)
             .where("batches.expires_on < ?", Date.current)
             .distinct.count
  end

  def calculate_expiry_value_risk
    Inventory.joins(:batches)
             .where("batches.expires_on <= ?", Date.current + 30.days)
             .sum("inventories.price * batches.quantity")
  end

  def generate_expiry_recommendations
    [
      "\u671F\u9650\u5207\u308C\u9593\u8FD1\u5546\u54C1\u306E\u7279\u5225\u4FA1\u683C\u3067\u306E\u8CA9\u58F2\u3092\u691C\u8A0E",
      "\u5728\u5EAB\u56DE\u8EE2\u7387\u306E\u6539\u5584\u306B\u3088\u308B\u671F\u9650\u5207\u308C\u30EA\u30B9\u30AF\u8EFD\u6E1B",
      "\u767A\u6CE8\u91CF\u306E\u6700\u9069\u5316\u306B\u3088\u308B\u904E\u5270\u5728\u5EAB\u306E\u9632\u6B62"
    ]
  end

  def calculate_inventory_turnover
    # 在庫回転率 = 売上原価 / 平均在庫金額
    # 将来的に売上データができた際の実装
    0
  end

  def calculate_stock_accuracy
    # 在庫精度 = 正確な在庫数 / 総在庫数
    # 将来的に棚卸機能ができた際の実装
    95.0
  end

  def calculate_fulfillment_rate
    # 充足率 = 要求を満たせた注文 / 総注文数
    # 将来的に注文管理ができた際の実装
    98.5
  end

  def calculate_carrying_cost
    # 在庫保有コスト
    # 倉庫コスト、保険料、機会費用等の計算
    Inventory.sum("quantity * price") * 0.15 # 15%と仮定
  end

  def count_stockout_incidents(target_date)
    # 在庫切れインシデント数
    # InventoryLogから在庫ゼロになった回数を集計
    InventoryLog.where(created_at: target_date..target_date.end_of_month)
                .where(operation_type: "sold")
                .joins(:inventory)
                .where("inventories.quantity = 0")
                .count
  end

  # TODO: 将来的な機能拡張
  # Phase 3（優先度：中、推定：3-4週間）
  # 関連: docs/design/job_processing_design.md
  # ============================================
  # 1. レポートテンプレート機能
  #    - カスタムレポートテンプレートの作成
  #    - 部門別・用途別のレポート形式
  #    - グラフ・チャート生成機能
  #
  # 2. 自動配信機能
  #    - 定期的なレポート自動生成
  #    - メール自動配信
  #    - ダッシュボード連携
  #
  # 3. 高度な分析機能
  #    - 機械学習による需要予測
  #    - 異常検知アルゴリズム
  #    - 最適在庫レベルの提案
  #
  # 4. 外部連携機能
  #    - 会計システムとの連携
  #    - BI ツールへのデータエクスポート
  #    - API経由での外部レポート配信
end
