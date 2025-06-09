# frozen_string_literal: true

# ============================================================================
# ExpiryAnalysisService - 期限切れ分析サービス
# ============================================================================
# 目的:
#   - Batchモデルの期限データを基にした期限切れリスク分析
#   - 期限切れ予測と対策提案
#   - ロス削減のための最適化提案
#
# 設計思想:
#   - 期限管理に特化した分析ロジック
#   - リスクレベル別の分類機能
#   - 予防的アクション提案機能
#
# 横展開確認:
#   - 他サービスクラスと同様のエラーハンドリング
#   - 一貫したデータ構造とメソッド命名
#   - 共通的なバリデーション方式
# ============================================================================

class ExpiryAnalysisService
  # ============================================================================
  # エラークラス
  # ============================================================================
  class ExpiryDataNotFoundError < StandardError; end
  class ExpiryAnalysisError < StandardError; end

  # ============================================================================
  # 定数定義
  # ============================================================================
  RISK_PERIODS = {
    immediate: 3.days,    # 即座リスク（3日以内）
    short_term: 7.days,   # 短期リスク（1週間以内）
    medium_term: 30.days, # 中期リスク（1ヶ月以内）
    long_term: 90.days    # 長期リスク（3ヶ月以内）
  }.freeze

  PRIORITY_LEVELS = %w[critical high medium low].freeze

  class << self
    # ============================================================================
    # 公開API
    # ============================================================================

    # 月次期限切れレポート生成
    # @param target_month [Date] 対象月
    # @param options [Hash] 分析オプション
    # @return [Hash] 期限切れ分析データ
    def monthly_report(target_month, options = {})
      validate_target_month!(target_month)

      Rails.logger.info "[ExpiryAnalysisService] Generating expiry report for #{target_month}"

      begin
        {
          target_date: target_month,
          expiry_summary: calculate_expiry_summary,
          risk_analysis: analyze_expiry_risks,
          financial_impact: calculate_financial_impact,
          trend_analysis: analyze_expiry_trends(target_month),
          recommendations: generate_recommendations,
          prevention_strategies: suggest_prevention_strategies,
          monitoring_alerts: generate_monitoring_alerts
        }
      rescue => e
        Rails.logger.error "[ExpiryAnalysisService] Error generating monthly report: #{e.message}"
        raise ExpiryAnalysisError, "月次期限切れレポート生成エラー: #{e.message}"
      end
    end

    # リスクレベル別分析
    # @param risk_level [Symbol] リスクレベル (:immediate, :short_term, :medium_term, :long_term)
    # @return [Hash] リスクレベル別データ
    def risk_level_analysis(risk_level = :all)
      validate_risk_level!(risk_level) unless risk_level == :all

      if risk_level == :all
        RISK_PERIODS.keys.map do |level|
          {
            risk_level: level,
            period: RISK_PERIODS[level],
            data: analyze_specific_risk_level(level)
          }
        end
      else
        analyze_specific_risk_level(risk_level)
      end
    end

    # 価値リスク分析
    # @param currency [String] 通貨単位（デフォルト: JPY）
    # @return [Hash] 金額ベースのリスク分析
    def value_risk_analysis(currency = "JPY")
      {
        currency: currency,
        total_at_risk: calculate_total_value_at_risk,
        risk_by_period: calculate_value_risk_by_period,
        high_value_items: identify_high_value_expiry_items,
        cost_optimization: calculate_cost_optimization_potential
      }
    end

    # 期限切れ予測
    # @param forecast_days [Integer] 予測期間（日数）
    # @return [Hash] 予測データ
    def expiry_forecast(forecast_days = 90)
      {
        forecast_period: forecast_days,
        predicted_expiries: predict_expiries(forecast_days),
        seasonal_adjustments: calculate_seasonal_adjustments,
        confidence_intervals: calculate_confidence_intervals(forecast_days),
        recommended_actions: generate_forecast_actions(forecast_days)
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
    end

    def validate_risk_level!(risk_level)
      unless RISK_PERIODS.key?(risk_level)
        raise ArgumentError, "Invalid risk_level: #{risk_level}. Valid options: #{RISK_PERIODS.keys.join(', ')}"
      end
    end

    # ============================================================================
    # 基本分析メソッド
    # ============================================================================

    def calculate_expiry_summary
      current_date = Date.current

      {
        expired_items: count_expired_items,
        expiring_soon: count_expiring_items(RISK_PERIODS[:immediate]),
        expiring_this_week: count_expiring_items(RISK_PERIODS[:short_term]),
        expiring_this_month: count_expiring_items(RISK_PERIODS[:medium_term]),
        expiring_this_quarter: count_expiring_items(RISK_PERIODS[:long_term]),
        total_monitored_items: count_total_monitored_items,
        expiry_rate: calculate_expiry_rate,
        improvement_from_last_month: calculate_month_over_month_improvement
      }
    end

    def analyze_expiry_risks
      RISK_PERIODS.map do |level, period|
        items = get_expiring_items(period)

        {
          risk_level: level,
          period_days: period.to_i / 1.day,
          items_count: items.count,
          total_value: calculate_items_value(items),
          average_value_per_item: calculate_average_value(items),
          priority_items: categorize_priority_items(items),
          action_required: determine_action_required(level, items)
        }
      end
    end

    def calculate_financial_impact
      expired_value = calculate_expired_items_value
      at_risk_value = calculate_total_value_at_risk

      {
        expired_loss: expired_value,
        potential_loss: at_risk_value,
        total_exposure: expired_value + at_risk_value,
        loss_percentage: calculate_loss_percentage(expired_value, at_risk_value),
        monthly_loss_trend: calculate_monthly_loss_trend,
        cost_of_prevention: estimate_prevention_costs,
        roi_of_prevention: calculate_prevention_roi
      }
    end

    def analyze_expiry_trends(target_month)
      # 過去12ヶ月のトレンド分析
      months_data = (1..12).map do |offset|
        month = target_month - offset.months
        {
          month: month,
          expired_count: count_expired_items_for_month(month),
          expired_value: calculate_expired_value_for_month(month),
          prevention_rate: calculate_prevention_rate_for_month(month)
        }
      end

      {
        historical_data: months_data,
        trend_direction: calculate_trend_direction(months_data),
        seasonality: analyze_seasonality(months_data),
        forecast: generate_trend_forecast(months_data)
      }
    end

    # ============================================================================
    # 詳細分析メソッド
    # ============================================================================

    def analyze_specific_risk_level(risk_level)
      period = RISK_PERIODS[risk_level]
      items = get_expiring_items(period)

      {
        risk_level: risk_level,
        period: period,
        summary: {
          total_items: items.count,
          total_value: calculate_items_value(items),
          average_days_to_expiry: calculate_average_days_to_expiry(items)
        },
        items_breakdown: categorize_items_by_value(items),
        urgency_ranking: rank_items_by_urgency(items),
        recommended_actions: generate_risk_specific_actions(risk_level, items)
      }
    end

    def calculate_total_value_at_risk
      total_value = 0

      RISK_PERIODS.each do |level, period|
        items = get_expiring_items(period)
        total_value += calculate_items_value(items)
      end

      total_value
    end

    def calculate_value_risk_by_period
      RISK_PERIODS.map do |level, period|
        items = get_expiring_items(period)
        value = calculate_items_value(items)

        {
          period: level,
          days: period.to_i / 1.day,
          items_count: items.count,
          value_at_risk: value,
          percentage_of_total: calculate_percentage(value, calculate_total_value_at_risk)
        }
      end
    end

    def identify_high_value_expiry_items(threshold = 10000)
      # 高価値期限切れアイテムの特定
      get_expiring_items(RISK_PERIODS[:long_term])
        .joins(:inventory)
        .where("inventories.price >= ?", threshold)
        .includes(:inventory)
        .map do |batch|
          {
            inventory_id: batch.inventory.id,
            inventory_name: batch.inventory.name,
            price: batch.inventory.price,
            quantity: batch.quantity,
            total_value: batch.inventory.price * batch.quantity,
            expires_on: batch.expires_on,
            days_until_expiry: (batch.expires_on - Date.current).to_i,
            priority: determine_priority_level(batch)
          }
        end
        .sort_by { |item| item[:total_value] }
        .reverse
    end

    def calculate_cost_optimization_potential
      # TODO: 🔴 Phase 1（緊急）- コスト最適化ポテンシャル計算の実装
      # 優先度: 高（経営判断指標）
      # 実装内容:
      #   - 早期販売による回収可能額の計算
      #   - 処分コスト vs 保管コストの比較
      #   - 値引き販売の最適タイミング算出
      # 横展開確認: 他の財務分析サービスとの計算方式統一

      {
        early_sale_potential: 0, # TODO: 実装
        disposal_cost_savings: 0, # TODO: 実装
        markdown_optimization: 0, # TODO: 実装
        total_optimization: 0 # TODO: 実装
      }
    end

    # ============================================================================
    # 予測分析メソッド
    # ============================================================================

    def predict_expiries(forecast_days)
      end_date = Date.current + forecast_days.days

      # 期間内に期限切れになる予定のアイテム
      upcoming_expiries = Batch.joins(:inventory)
                              .where(expires_on: Date.current..end_date)
                              .includes(:inventory)

      # 日別の予測データ
      daily_forecast = (Date.current..end_date).map do |date|
        daily_expiries = upcoming_expiries.select { |batch| batch.expires_on == date }

        {
          date: date,
          expiring_items: daily_expiries.count,
          expiring_value: daily_expiries.sum { |batch| batch.inventory.price * batch.quantity },
          items_details: daily_expiries.map do |batch|
            {
              inventory_name: batch.inventory.name,
              quantity: batch.quantity,
              value: batch.inventory.price * batch.quantity
            }
          end
        }
      end

      {
        daily_forecast: daily_forecast,
        weekly_summary: group_forecast_by_week(daily_forecast),
        monthly_summary: group_forecast_by_month(daily_forecast),
        peak_expiry_dates: identify_peak_expiry_dates(daily_forecast)
      }
    end

    def calculate_seasonal_adjustments
      # TODO: 🟡 Phase 2（中）- より高度な季節性分析
      # 優先度: 中（予測精度向上）
      # 実装内容: 過去データの季節パターン分析
      {
        seasonal_factor: 1.0,
        peak_seasons: [],
        adjustment_confidence: 0.5
      }
    end

    def calculate_confidence_intervals(forecast_days)
      # 予測の信頼区間計算
      # TODO: 統計的モデルベースの信頼区間計算
      {
        confidence_level: 0.95,
        lower_bound: 0.8,
        upper_bound: 1.2,
        prediction_accuracy: 0.85
      }
    end

    def generate_forecast_actions(forecast_days)
      upcoming_expiries = predict_expiries(forecast_days)
      actions = []

      # 重大な期限切れイベントの特定
      upcoming_expiries[:daily_forecast].each do |day_data|
        if day_data[:expiring_value] > 50000 # 閾値
          actions << {
            date: day_data[:date],
            type: "high_value_expiry_alert",
            priority: "high",
            action: "#{day_data[:date]}に高価値アイテム（#{day_data[:expiring_value]}円相当）が期限切れ予定です。早期対応が必要です。",
            recommended_response: "即座に割引販売または代替処分方法を検討"
          }
        end
      end

      actions
    end

    # ============================================================================
    # レコメンデーション生成
    # ============================================================================

    def generate_recommendations
      recommendations = []

      # 即座対応が必要なアイテム
      immediate_items = get_expiring_items(RISK_PERIODS[:immediate])
      if immediate_items.any?
        recommendations << {
          priority: "critical",
          category: "immediate_action",
          title: "緊急：3日以内期限切れアイテム対応",
          description: "#{immediate_items.count}件のアイテムが3日以内に期限切れになります。",
          actions: [
            "即座に割引販売を実施",
            "スタッフ購入制度の活用",
            "食品バンクへの寄付検討"
          ],
          impact: "high",
          effort: "low"
        }
      end

      # 予防的対策
      medium_term_items = get_expiring_items(RISK_PERIODS[:medium_term])
      if medium_term_items.count > 10
        recommendations << {
          priority: "high",
          category: "prevention",
          title: "在庫回転率改善による期限切れ防止",
          description: "1ヶ月以内期限切れアイテムが多数存在します（#{medium_term_items.count}件）。",
          actions: [
            "FIFO（先入先出）の徹底",
            "発注量の最適化",
            "販売促進キャンペーンの実施"
          ],
          impact: "medium",
          effort: "medium"
        }
      end

      # TODO: 🟠 Phase 2（重要）- AI/機械学習による高度な推奨機能
      # 優先度: 高（付加価値向上）
      # 実装内容:
      #   - 過去パターンからの学習
      #   - 需要予測に基づく最適化提案
      #   - 個別アイテム特性を考慮した提案

      recommendations
    end

    def suggest_prevention_strategies
      [
        {
          strategy: "在庫管理システム改善",
          description: "期限切れアラート機能の強化",
          implementation_cost: "低",
          expected_roi: "高",
          timeline: "1ヶ月"
        },
        {
          strategy: "販売戦略最適化",
          description: "期限間近商品の自動割引システム",
          implementation_cost: "中",
          expected_roi: "高",
          timeline: "2ヶ月"
        },
        {
          strategy: "サプライチェーン最適化",
          description: "発注頻度と量の動的調整",
          implementation_cost: "高",
          expected_roi: "中",
          timeline: "6ヶ月"
        }
      ]
    end

    def generate_monitoring_alerts
      alerts = []

      # 閾値ベースのアラート設定
      immediate_count = count_expiring_items(RISK_PERIODS[:immediate])
      if immediate_count > 5
        alerts << {
          type: "critical",
          message: "即座対応必要：#{immediate_count}件のアイテムが3日以内に期限切れ",
          action_required: true,
          escalation_level: 1
        }
      end

      weekly_count = count_expiring_items(RISK_PERIODS[:short_term])
      if weekly_count > 20
        alerts << {
          type: "warning",
          message: "注意：#{weekly_count}件のアイテムが1週間以内に期限切れ",
          action_required: false,
          escalation_level: 2
        }
      end

      alerts
    end

    # ============================================================================
    # ヘルパーメソッド
    # ============================================================================

    def count_expired_items
      Batch.where("expires_on < ?", Date.current).count
    end

    def count_expiring_items(period)
      Batch.where(expires_on: Date.current..(Date.current + period)).count
    end

    def count_total_monitored_items
      Batch.where.not(expires_on: nil).count
    end

    def get_expiring_items(period)
      Batch.where(expires_on: Date.current..(Date.current + period))
    end

    def calculate_items_value(items)
      items.joins(:inventory).sum("inventories.price * batches.quantity")
    end

    def calculate_average_value(items)
      return 0 if items.empty?
      calculate_items_value(items).to_f / items.count
    end

    def calculate_expiry_rate
      total_items = count_total_monitored_items
      expired_items = count_expired_items

      return 0 if total_items.zero?
      (expired_items.to_f / total_items * 100).round(2)
    end

    def calculate_month_over_month_improvement
      # TODO: 前月比較の実装
      0
    end

    def calculate_expired_items_value
      Batch.joins(:inventory)
           .where("expires_on < ?", Date.current)
           .sum("inventories.price * batches.quantity")
    end

    def calculate_loss_percentage(expired_value, at_risk_value)
      total_inventory_value = Inventory.sum("quantity * price")
      return 0 if total_inventory_value.zero?

      ((expired_value + at_risk_value) / total_inventory_value * 100).round(2)
    end

    def calculate_monthly_loss_trend
      # TODO: 月次ロストレンドの計算
      []
    end

    def estimate_prevention_costs
      # TODO: 予防コストの見積
      0
    end

    def calculate_prevention_roi
      # TODO: 予防策のROI計算
      0
    end

    def categorize_priority_items(items)
      items.map do |item|
        {
          item: item,
          priority: determine_priority_level(item),
          urgency_score: calculate_urgency_score(item)
        }
      end.group_by { |item| item[:priority] }
    end

    def determine_action_required(risk_level, items)
      case risk_level
      when :immediate then "immediate_action_required"
      when :short_term then "action_recommended"
      when :medium_term then "monitoring_advised"
      when :long_term then "awareness_only"
      end
    end

    def determine_priority_level(batch)
      days_until_expiry = (batch.expires_on - Date.current).to_i
      value = batch.inventory.price * batch.quantity

      case days_until_expiry
      when 0..3
        value > 10000 ? "critical" : "high"
      when 4..7
        value > 5000 ? "high" : "medium"
      when 8..30
        value > 10000 ? "medium" : "low"
      else
        "low"
      end
    end

    def calculate_urgency_score(batch)
      days_until_expiry = (batch.expires_on - Date.current).to_i
      value = batch.inventory.price * batch.quantity

      # 日数の逆数 + 価値係数
      time_factor = 100.0 / [ days_until_expiry, 1 ].max
      value_factor = value / 1000.0

      (time_factor + value_factor).round(2)
    end

    def categorize_items_by_value(items)
      # 価値別カテゴリ分類
      {
        high_value: items.joins(:inventory).where("inventories.price * batches.quantity >= ?", 10000),
        medium_value: items.joins(:inventory).where("inventories.price * batches.quantity BETWEEN ? AND ?", 1000, 9999),
        low_value: items.joins(:inventory).where("inventories.price * batches.quantity < ?", 1000)
      }
    end

    def rank_items_by_urgency(items)
      items.map do |item|
        {
          item: item,
          urgency_score: calculate_urgency_score(item)
        }
      end.sort_by { |ranked| ranked[:urgency_score] }.reverse.first(10)
    end

    def generate_risk_specific_actions(risk_level, items)
      case risk_level
      when :immediate
        [ "即座に割引販売", "スタッフ販売", "廃棄準備" ]
      when :short_term
        [ "販促キャンペーン", "バンドル販売", "法人営業" ]
      when :medium_term
        [ "在庫調整", "発注量見直し", "販売戦略検討" ]
      when :long_term
        [ "モニタリング継続", "予防策検討" ]
      end
    end

    def calculate_percentage(part, total)
      return 0 if total.zero?
      (part.to_f / total * 100).round(2)
    end

    def calculate_average_days_to_expiry(items)
      return 0 if items.empty?

      total_days = items.sum { |item| (item.expires_on - Date.current).to_i }
      (total_days.to_f / items.count).round(1)
    end

    def count_expired_items_for_month(month)
      # TODO: 月次期限切れ集計の実装
      0
    end

    def calculate_expired_value_for_month(month)
      # TODO: 月次期限切れ価値の計算
      0
    end

    def calculate_prevention_rate_for_month(month)
      # TODO: 月次予防率の計算
      0
    end

    def calculate_trend_direction(months_data)
      return "stable" if months_data.length < 3

      recent = months_data.last(3).sum { |m| m[:expired_count] }
      earlier = months_data.first(3).sum { |m| m[:expired_count] }

      if recent > earlier * 1.1
        "worsening"
      elsif recent < earlier * 0.9
        "improving"
      else
        "stable"
      end
    end

    def analyze_seasonality(months_data)
      # TODO: より高度な季節性分析
      {
        has_seasonality: false,
        peak_months: [],
        seasonal_strength: 0
      }
    end

    def generate_trend_forecast(months_data)
      # TODO: トレンド予測の実装
      {
        next_month_prediction: 0,
        confidence: 0.5,
        trend: "stable"
      }
    end

    def group_forecast_by_week(daily_forecast)
      daily_forecast.group_by { |day| day[:date].beginning_of_week }
                   .map do |week_start, days|
                     {
                       week_start: week_start,
                       total_expiring: days.sum { |day| day[:expiring_items] },
                       total_value: days.sum { |day| day[:expiring_value] }
                     }
                   end
    end

    def group_forecast_by_month(daily_forecast)
      daily_forecast.group_by { |day| day[:date].beginning_of_month }
                   .map do |month_start, days|
                     {
                       month_start: month_start,
                       total_expiring: days.sum { |day| day[:expiring_items] },
                       total_value: days.sum { |day| day[:expiring_value] }
                     }
                   end
    end

    def identify_peak_expiry_dates(daily_forecast)
      avg_items = daily_forecast.sum { |day| day[:expiring_items] }.to_f / daily_forecast.length
      threshold = avg_items * 2

      daily_forecast.select { |day| day[:expiring_items] > threshold }
                   .sort_by { |day| day[:expiring_items] }
                   .reverse
                   .first(5)
    end
  end
end
