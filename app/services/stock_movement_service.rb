# frozen_string_literal: true

# ============================================================================
# StockMovementService - 在庫移動・動向分析サービス
# ============================================================================
# 目的:
#   - InventoryLogを基にした在庫移動パターンの分析
#   - 入出庫傾向の可視化とレポート生成
#   - 在庫動向の予測データ提供
#
# 設計思想:
#   - InventoryReportServiceとの責任分離
#   - ログデータに特化した分析ロジック
#   - 時系列分析機能の提供
#
# 横展開確認:
#   - InventoryReportServiceと同様のエラーハンドリングパターン
#   - 一貫したメソッド命名規則
#   - 同じバリデーション方式
# ============================================================================

class StockMovementService
  # ============================================================================
  # エラークラス
  # ============================================================================
  class MovementDataNotFoundError < StandardError; end
  class AnalysisError < StandardError; end

  # ============================================================================
  # 定数定義
  # ============================================================================
  MOVEMENT_TYPES = %w[received sold adjusted returned damaged].freeze
  ANALYSIS_PERIOD_DAYS = 30
  HIGH_ACTIVITY_THRESHOLD = 10

  class << self
    # ============================================================================
    # 公開API
    # ============================================================================

    # 月次在庫移動分析
    # @param target_month [Date] 対象月
    # @param options [Hash] 分析オプション
    # @return [Hash] 在庫移動分析データ
    def monthly_analysis(target_month, options = {})
      validate_target_month!(target_month)

      Rails.logger.info "[StockMovementService] Analyzing stock movements for #{target_month}"

      begin
        end_of_month = target_month.end_of_month

        {
          target_date: target_month,
          total_movements: calculate_total_movements(target_month, end_of_month),
          movement_breakdown: calculate_movement_breakdown(target_month, end_of_month),
          top_active_items: identify_top_active_items(target_month, end_of_month),
          movement_trends: analyze_movement_trends(target_month, end_of_month),
          velocity_analysis: calculate_velocity_analysis(target_month, end_of_month),
          seasonal_patterns: analyze_seasonal_patterns(target_month),
          movement_efficiency: calculate_movement_efficiency(target_month, end_of_month)
        }
      rescue => e
        Rails.logger.error "[StockMovementService] Error in monthly analysis: #{e.message}"
        raise AnalysisError, "月次移動分析エラー: #{e.message}"
      end
    end

    # 在庫移動速度分析
    # @param inventory_ids [Array<Integer>] 対象在庫ID（nilの場合は全件）
    # @param period_days [Integer] 分析期間（日数）
    # @return [Hash] 移動速度分析データ
    def velocity_analysis(inventory_ids = nil, period_days = ANALYSIS_PERIOD_DAYS)
      target_inventories = inventory_ids ? Inventory.where(id: inventory_ids) : Inventory.all
      start_date = Date.current - period_days.days

      {
        analysis_period: period_days,
        fast_moving_items: identify_fast_moving_items(target_inventories, start_date),
        slow_moving_items: identify_slow_moving_items(target_inventories, start_date),
        average_turnover: calculate_average_turnover(target_inventories, start_date),
        movement_distribution: calculate_movement_distribution(target_inventories, start_date)
      }
    end

    # リアルタイム活動監視
    # @param hours [Integer] 監視期間（時間）
    # @return [Hash] リアルタイム活動データ
    def real_time_activity(hours = 24)
      start_time = Time.current - hours.hours

      {
        period_hours: hours,
        recent_movements: get_recent_movements(start_time),
        activity_heatmap: generate_activity_heatmap(start_time),
        alert_items: identify_alert_items(start_time),
        movement_summary: summarize_recent_movements(start_time)
      }
    end

    private

    # ============================================================================
    # バリデーション
    # ============================================================================

    def validate_target_month!(target_month)
      unless target_month.is_a?(Date)
        raise ArgumentError, "target_month must be a Date object"
      end

      if target_month > Date.current
        raise ArgumentError, "target_month cannot be in the future"
      end
    end

    # ============================================================================
    # 基本分析メソッド
    # ============================================================================

    def calculate_total_movements(start_date, end_date)
      InventoryLog.where(created_at: start_date..end_date).count
    end

    def calculate_movement_breakdown(start_date, end_date)
      breakdown = InventoryLog.where(created_at: start_date..end_date)
                            .group(:operation_type)
                            .count

      # TODO: 🟠 Phase 2（重要）- 操作タイプの統一
      # 優先度: 高（データ整合性）
      # 実装内容: operation_typeの標準化とバリデーション
      # 横展開確認: 他のログ分析処理での同様対応

      MOVEMENT_TYPES.map do |type|
        {
          type: type,
          count: breakdown[type] || 0,
          percentage: calculate_percentage(breakdown[type] || 0, breakdown.values.sum)
        }
      end
    end

    def identify_top_active_items(start_date, end_date, limit = 10)
      InventoryLog.joins(:inventory)
                 .where(created_at: start_date..end_date)
                 .group(:inventory_id, "inventories.name")
                 .order("COUNT(*) DESC")
                 .limit(limit)
                 .count
                 .map do |key, count|
                   inventory_id, name = key
                   {
                     inventory_id: inventory_id,
                     name: name,
                     movement_count: count,
                     activity_score: calculate_activity_score(inventory_id, start_date, end_date)
                   }
                 end
    end

    def analyze_movement_trends(start_date, end_date)
      # 日別移動トレンドの分析
      daily_movements = InventoryLog.where(created_at: start_date..end_date)
                                  .group("DATE(created_at)")
                                  .count

      dates = (start_date.to_date..end_date.to_date).to_a
      trend_data = dates.map do |date|
        {
          date: date,
          movements: daily_movements[date] || 0
        }
      end

      {
        daily_data: trend_data,
        trend_direction: calculate_trend_direction(trend_data),
        peak_days: identify_peak_days(trend_data),
        average_daily_movements: daily_movements.values.sum.to_f / dates.length
      }
    end

    def calculate_velocity_analysis(start_date, end_date)
      # TODO: 🔴 Phase 1（緊急）- 在庫回転率の正確な計算
      # 優先度: 高（重要指標）
      # 実装内容:
      #   - 期間開始・終了時の在庫量考慮
      #   - 平均在庫量の正確な計算
      #   - 業界標準指標との整合性確保
      # 横展開確認: InventoryReportServiceとの計算方式統一

      {
        inventory_turnover: 0, # TODO: 実装
        days_sales_outstanding: 0, # TODO: 実装
        stock_rotation_frequency: 0, # TODO: 実装
        velocity_categories: categorize_by_velocity
      }
    end

    # ============================================================================
    # 高度な分析メソッド
    # ============================================================================

    def analyze_seasonal_patterns(target_month)
      # 過去12ヶ月のデータを使った季節性分析
      months_data = (1..12).map do |month_offset|
        analysis_month = target_month - month_offset.months
        movement_count = InventoryLog.where(
          created_at: analysis_month..analysis_month.end_of_month
        ).count

        {
          month: analysis_month,
          movements: movement_count,
          seasonal_index: calculate_seasonal_index(movement_count, target_month)
        }
      end

      {
        historical_data: months_data,
        seasonal_strength: calculate_seasonal_strength(months_data),
        forecast_adjustment: calculate_forecast_adjustment(months_data)
      }
    end

    def calculate_movement_efficiency(start_date, end_date)
      total_movements = calculate_total_movements(start_date, end_date)
      error_movements = InventoryLog.where(
        created_at: start_date..end_date,
        operation_type: %w[adjusted returned damaged]
      ).count

      {
        total_movements: total_movements,
        error_movements: error_movements,
        efficiency_rate: calculate_percentage(total_movements - error_movements, total_movements),
        error_rate: calculate_percentage(error_movements, total_movements),
        recommendations: generate_efficiency_recommendations(error_movements, total_movements)
      }
    end

    # ============================================================================
    # 速度分析メソッド
    # ============================================================================

    def identify_fast_moving_items(inventories, start_date, threshold = HIGH_ACTIVITY_THRESHOLD)
      inventories.joins(:inventory_logs)
                .where(inventory_logs: { created_at: start_date.. })
                .group("inventories.id", "inventories.name")
                .having("COUNT(inventory_logs.id) >= ?", threshold)
                .order("COUNT(inventory_logs.id) DESC")
                .count
                .map do |key, count|
                  inventory_id, name = key
                  {
                    inventory_id: inventory_id,
                    name: name,
                    movement_count: count,
                    velocity_score: calculate_velocity_score(count, start_date)
                  }
                end
    end

    def identify_slow_moving_items(inventories, start_date, threshold = 2)
      # 移動が少ない（閾値以下）アイテムの特定
      fast_moving_ids = identify_fast_moving_items(inventories, start_date).map { |item| item[:inventory_id] }

      inventories.where.not(id: fast_moving_ids)
                .joins("LEFT JOIN inventory_logs ON inventory_logs.inventory_id = inventories.id AND inventory_logs.created_at >= '#{start_date}'")
                .group("inventories.id", "inventories.name")
                .having("COUNT(inventory_logs.id) <= ?", threshold)
                .order("COUNT(inventory_logs.id) ASC")
                .count
                .map do |key, count|
                  inventory_id, name = key
                  {
                    inventory_id: inventory_id,
                    name: name,
                    movement_count: count,
                    risk_level: calculate_stagnation_risk(count, start_date)
                  }
                end
    end

    def calculate_average_turnover(inventories, start_date)
      period_days = (Date.current - start_date.to_date).to_i
      total_movements = inventories.joins(:inventory_logs)
                                 .where(inventory_logs: { created_at: start_date.. })
                                 .count

      return 0 if inventories.count.zero? || period_days.zero?

      (total_movements.to_f / inventories.count / period_days * 30).round(2) # 月次平均
    end

    def calculate_movement_distribution(inventories, start_date)
      # 移動頻度の分布計算
      movement_counts = inventories.joins("LEFT JOIN inventory_logs ON inventory_logs.inventory_id = inventories.id AND inventory_logs.created_at >= '#{start_date}'")
                                 .group("inventories.id")
                                 .count("inventory_logs.id")

      ranges = [
        { min: 0, max: 1, label: "ほぼ動きなし" },
        { min: 2, max: 5, label: "低活動" },
        { min: 6, max: 15, label: "中活動" },
        { min: 16, max: Float::INFINITY, label: "高活動" }
      ]

      ranges.map do |range|
        count = movement_counts.values.count do |movements|
          if range[:max] == Float::INFINITY
            movements >= range[:min]
          else
            movements.between?(range[:min], range[:max])
          end
        end

        {
          label: range[:label],
          range: range[:max] == Float::INFINITY ? "#{range[:min]}+" : "#{range[:min]}-#{range[:max]}",
          count: count,
          percentage: calculate_percentage(count, inventories.count)
        }
      end
    end

    # ============================================================================
    # リアルタイム分析メソッド
    # ============================================================================

    def get_recent_movements(start_time, limit = 50)
      InventoryLog.includes(:inventory)
                 .where(created_at: start_time..)
                 .order(created_at: :desc)
                 .limit(limit)
                 .map do |log|
                   {
                     id: log.id,
                     inventory_name: log.inventory.name,
                     operation_type: log.operation_type,
                     quantity_change: log.quantity_change,
                     created_at: log.created_at,
                     time_ago: time_ago_in_words(log.created_at)
                   }
                 end
    end

    def generate_activity_heatmap(start_time)
      # 時間別活動ヒートマップ（24時間 x 7日）
      hourly_data = InventoryLog.where(created_at: start_time..)
                              .group("HOUR(created_at)")
                              .group("DAYOFWEEK(created_at)")
                              .count

      (0..23).map do |hour|
        {
          hour: hour,
          daily_activity: (1..7).map do |day|
            {
              day: day,
              activity: hourly_data[[ hour, day ]] || 0
            }
          end
        }
      end
    end

    def identify_alert_items(start_time)
      # 異常な動きを示すアイテムの特定
      recent_high_activity = InventoryLog.joins(:inventory)
                                       .where(created_at: start_time..)
                                       .group(:inventory_id, "inventories.name")
                                       .having("COUNT(*) > ?", HIGH_ACTIVITY_THRESHOLD)
                                       .count

      recent_high_activity.map do |key, count|
        inventory_id, name = key
        {
          inventory_id: inventory_id,
          name: name,
          recent_activity: count,
          alert_type: determine_alert_type(inventory_id, count, start_time),
          priority: calculate_alert_priority(count)
        }
      end
    end

    def summarize_recent_movements(start_time)
      movements = InventoryLog.where(created_at: start_time..)

      {
        total_movements: movements.count,
        by_type: movements.group(:operation_type).count,
        unique_items: movements.distinct.count(:inventory_id),
        average_per_hour: (movements.count.to_f / ((Time.current - start_time) / 1.hour)).round(2)
      }
    end

    # ============================================================================
    # ヘルパーメソッド
    # ============================================================================

    def calculate_percentage(part, total)
      return 0 if total.zero?
      (part.to_f / total * 100).round(2)
    end

    def calculate_activity_score(inventory_id, start_date, end_date)
      # アクティビティスコア（0-100）
      movement_count = InventoryLog.where(
        inventory_id: inventory_id,
        created_at: start_date..end_date
      ).count

      [ movement_count * 10, 100 ].min
    end

    def calculate_trend_direction(trend_data)
      return "stable" if trend_data.length < 3

      recent_values = trend_data.last(7).map { |d| d[:movements] }
      early_values = trend_data.first(7).map { |d| d[:movements] }

      recent_avg = recent_values.sum.to_f / recent_values.length
      early_avg = early_values.sum.to_f / early_values.length

      if recent_avg > early_avg * 1.1
        "increasing"
      elsif recent_avg < early_avg * 0.9
        "decreasing"
      else
        "stable"
      end
    end

    def identify_peak_days(trend_data)
      return [] if trend_data.length < 3

      avg_movements = trend_data.map { |d| d[:movements] }.sum.to_f / trend_data.length
      threshold = avg_movements * 1.5

      trend_data.select { |d| d[:movements] > threshold }
               .map { |d| d[:date] }
    end

    def categorize_by_velocity
      # TODO: 🟡 Phase 2（中）- より詳細な速度カテゴリ分類
      # 優先度: 中（分析精度向上）
      # 実装内容: 業界標準に基づく速度分類
      {
        "A級（高速回転）" => 0,
        "B級（中速回転）" => 0,
        "C級（低速回転）" => 0,
        "D級（停滞）" => 0
      }
    end

    def calculate_seasonal_index(movement_count, base_month)
      # 季節指数の計算（1.0が平均）
      # TODO: より高度な季節性分析の実装
      1.0
    end

    def calculate_seasonal_strength(months_data)
      return 0 if months_data.length < 12

      movements = months_data.map { |m| m[:movements] }
      avg = movements.sum.to_f / movements.length
      variance = movements.map { |m| (m - avg) ** 2 }.sum / movements.length

      (Math.sqrt(variance) / avg * 100).round(2)
    end

    def calculate_forecast_adjustment(months_data)
      # 予測調整係数
      # TODO: より高度な予測モデルの実装
      1.0
    end

    def generate_efficiency_recommendations(error_movements, total_movements)
      recommendations = []

      error_rate = calculate_percentage(error_movements, total_movements)

      if error_rate > 10
        recommendations << {
          type: "warning",
          message: "エラー率が高すぎます（#{error_rate}%）。作業プロセスの見直しが必要です。"
        }
      end

      if error_rate > 5
        recommendations << {
          type: "info",
          message: "品質管理の強化を検討してください。"
        }
      end

      recommendations
    end

    def calculate_velocity_score(movement_count, start_date)
      period_days = (Date.current - start_date.to_date).to_i
      daily_avg = movement_count.to_f / period_days

      # スコア化（0-100）
      [ daily_avg * 20, 100 ].min.round(1)
    end

    def calculate_stagnation_risk(movement_count, start_date)
      period_days = (Date.current - start_date.to_date).to_i

      if movement_count.zero?
        "high"
      elsif movement_count < period_days * 0.1
        "medium"
      else
        "low"
      end
    end

    def determine_alert_type(inventory_id, count, start_time)
      # アラートタイプの判定ロジック
      period_hours = (Time.current - start_time) / 1.hour

      if count > period_hours * 2
        "high_frequency"
      elsif count > HIGH_ACTIVITY_THRESHOLD
        "unusual_activity"
      else
        "normal"
      end
    end

    def calculate_alert_priority(count)
      case count
      when 0..5 then "low"
      when 6..15 then "medium"
      else "high"
      end
    end

    def time_ago_in_words(time)
      # 簡単な相対時間表示
      diff = Time.current - time

      case diff
      when 0..60 then "#{diff.to_i}秒前"
      when 61..3600 then "#{(diff / 60).to_i}分前"
      when 3601..86400 then "#{(diff / 3600).to_i}時間前"
      else "#{(diff / 86400).to_i}日前"
      end
    end
  end
end
