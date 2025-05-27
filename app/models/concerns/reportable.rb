# frozen_string_literal: true

module Reportable
  extend ActiveSupport::Concern

  # インスタンスメソッド
  def generate_stock_report
    {
      id: id,
      name: name,
      current_quantity: quantity,
      value: quantity * price,
      status: stock_status,
      batches_count: respond_to?(:batches) ? batches.count : 0,
      last_updated: updated_at,
      nearest_expiry: respond_to?(:nearest_expiry_date) ? nearest_expiry_date : nil
    }
  end

  class_methods do
    # 在庫レポートの生成
    def generate_inventory_report(options = {})
      as_of_date = options[:as_of_date] || Time.current

      report_data = {
        generated_at: Time.current,
        as_of_date: as_of_date,
        total_items: count,
        total_value: sum("quantity * price"),
        low_stock_items: low_stock.count,
        out_of_stock_items: out_of_stock.count,
        items_by_status: {
          active: active.count,
          archived: where(status: :archived).count
        },
        summary: get_summary_data(as_of_date),
        details: get_detailed_data(options)
      }

      # 詳細情報を含める場合
      if options[:include_details]
        report_data[:items] = all.map(&:generate_stock_report)
      end

      # 過去比較データを含める場合
      if options[:compare_with_previous]
        previous_period = options[:compare_days] || 30
        previous_data = get_historical_data(previous_period.days.ago)

        report_data[:comparison] = {
          previous_total_items: previous_data[:total_items],
          previous_total_value: previous_data[:total_value],
          items_change: count - previous_data[:total_items],
          value_change: sum("quantity * price") - previous_data[:total_value],
          change_percentage: previous_data[:total_value].zero? ? 0 : ((sum("quantity * price") - previous_data[:total_value]) / previous_data[:total_value] * 100).round(2)
        }
      end

      # 比較データの追加
      if options[:compare_with]
        report_data[:comparison] = {
          previous_date: options[:compare_with],
          previous_data: get_historical_data(options[:compare_with]),
          current_data: get_historical_data(as_of_date),
          diff: {} # 差分は後で計算
        }

        # 差分の計算
        calculate_comparison_diff(report_data[:comparison])
      end

      # ファイル出力オプション
      if options[:output_file]
        output_report_to_file(report_data, options)
      end

      report_data
    end

    # 過去の在庫データを取得（既存データまたは在庫ログから再構築）
    def get_historical_data(date)
      # 必要な在庫IDを全て取得
      ids_from_logs = InventoryLog.where("created_at <= ?", date).distinct.pluck(:inventory_id)

      # 在庫データを一括取得（N+1回避）
      inventory_prices = where(id: ids_from_logs).pluck(:id, :price).to_h

      # 在庫IDごとの最新ログエントリを取得するサブクエリ
      latest_logs_subquery = InventoryLog.where("created_at <= ?", date)
                                        .select("DISTINCT ON (inventory_id) inventory_id, id, current_quantity")
                                        .order("inventory_id, created_at DESC")

      # 最新ログエントリを一括取得（N+1回避）
      latest_logs = InventoryLog.find_by_sql(latest_logs_subquery.to_sql)

      # ログエントリと価格情報を組み合わせて合計値を計算
      total_value = latest_logs.sum do |log|
        price = inventory_prices[log.inventory_id] || 0
        log.current_quantity * price
      end

      {
        total_count: ids_from_logs.size,
        total_value: total_value
      }
    end

    # CSV形式で在庫レポートをエクスポート
    def export_inventory_report_csv
      CSV.generate do |csv|
        csv << [ "ID", "\u5546\u54C1\u540D", "\u73FE\u5728\u6570\u91CF", "\u4FA1\u683C", "\u5408\u8A08\u91D1\u984D", "\u72B6\u614B", "\u30D0\u30C3\u30C1\u6570", "\u6700\u7D42\u66F4\u65B0\u65E5", "\u6700\u77ED\u671F\u9650\u65E5" ]

        all.find_each do |item|
          report = item.generate_stock_report
          csv << [
            report[:id],
            report[:name],
            report[:current_quantity],
            item.price,
            report[:value],
            report[:status],
            report[:batches_count],
            report[:last_updated].strftime("%Y-%m-%d %H:%M:%S"),
            report[:nearest_expiry]&.strftime("%Y-%m-%d")
          ]
        end
      end
    end

    # JSONで在庫分析データを生成
    def generate_analysis_json(options = {})
      report = generate_inventory_report(include_details: true)

      # APIやグラフ描画用にJSON形式で返す
      {
        summary: {
          total_items: report[:total_items],
          total_value: report[:total_value],
          low_stock_items: report[:low_stock_items],
          out_of_stock_items: report[:out_of_stock_items]
        },
        status_distribution: {
          active: report[:items_by_status][:active],
          archived: report[:items_by_status][:archived]
        },
        items: report[:items].map do |item|
          {
            id: item[:id],
            name: item[:name],
            quantity: item[:current_quantity],
            value: item[:value],
            status: item[:status]
          }
        end
      }.to_json
    end

    private

    # サマリーデータの取得
    def get_summary_data(date)
      {
        total_count: count,
        in_stock_count: where("quantity > 0").count,
        out_of_stock_count: where(quantity: 0).count,
        low_stock_count: where("quantity > 0 AND quantity <= 5").count,
        total_quantity: sum(:quantity),
        total_value: calculate_total_value,
        active_count: where(status: :active).count,
        archived_count: where(status: :archived).count
      }
    end

    # 詳細データの取得
    def get_detailed_data(options)
      items = all

      # フィルタリング
      items = items.where(status: options[:status]) if options[:status]
      items = items.where("quantity <= ?", options[:low_stock_threshold]) if options[:low_stock_only]
      items = items.where(quantity: 0) if options[:out_of_stock_only]

      # ソート
      if options[:sort_by]
        direction = options[:sort_direction] == :desc ? :desc : :asc
        items = items.order(options[:sort_by] => direction)
      end

      # 特定の項目だけ取得
      if options[:select_fields]
        items = items.select(options[:select_fields])
      end

      items
    end

    # 比較データの差分計算
    def calculate_comparison_diff(comparison)
      current = comparison[:current_data]
      previous = comparison[:previous_data]

      comparison[:diff] = {
        total_count_diff: current[:total_count] - previous[:total_count],
        total_count_percent: calculate_percent_change(previous[:total_count], current[:total_count]),
        total_value_diff: current[:total_value] - previous[:total_value],
        total_value_percent: calculate_percent_change(previous[:total_value], current[:total_value])
      }
    end

    # 変化率の計算
    def calculate_percent_change(old_value, new_value)
      return 0 if old_value.zero?
      ((new_value - old_value) / old_value.to_f * 100).round(2)
    end

    # 在庫価値の計算
    def calculate_total_value
      sum("quantity * price")
    end

    # レポートのファイル出力
    def output_report_to_file(report_data, options)
      file_format = options[:file_format] || :json
      file_path = options[:file_path] || Rails.root.join("tmp", "inventory_report_#{Time.current.to_i}.#{file_format}")

      case file_format.to_sym
      when :json
        File.write(file_path, report_data.to_json)
      when :csv
        output_report_to_csv(report_data, file_path)
      end

      file_path
    end

    # レポートのCSV出力
    def output_report_to_csv(report_data, file_path)
      require "csv"

      CSV.open(file_path, "wb") do |csv|
        # ヘッダー
        csv << [ "Inventory Report", "Generated at: #{report_data[:generated_at]}", "As of: #{report_data[:as_of_date]}" ]
        csv << []

        # サマリーセクション
        csv << [ "Summary" ]
        report_data[:summary].each do |key, value|
          csv << [ key.to_s.humanize, value ]
        end
        csv << []

        # 詳細セクション
        csv << [ "Details" ]
        if report_data[:details].any?
          # ヘッダー行
          csv << report_data[:details].first.attributes.keys

          # データ行
          report_data[:details].each do |item|
            csv << item.attributes.values
          end
        end
      end
    end

    # TODO: レポート機能の拡張
    # 1. ダッシュボード機能
    #    - リアルタイムKPI表示
    #    - 在庫アラートの一元管理
    #    - グラフィカルな在庫推移表示
    #
    # 2. 高度な分析機能
    #    - 売上予測レポート
    #    - 在庫効率性分析
    #    - カテゴリ別パフォーマンス比較
    #
    # 3. 自動レポート配信
    #    - 定期レポートのスケジューリング
    #    - メール・Slack等への自動配信
    #    - カスタムレポートテンプレート機能
  end
end
