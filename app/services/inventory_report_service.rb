# frozen_string_literal: true

# ============================================================================
# InventoryReportService - 在庫関連レポートデータ収集サービス
# ============================================================================
# 目的:
#   - 月次レポート用の在庫関連データを効率的に収集・計算
#   - MonthlyReportJobとの責任分離による保守性向上
#   - SOLID原則に基づく単一責任設計
#
# 設計思想:
#   - 計算ロジックの集約化
#   - テスト容易性の向上
#   - 既存MonthlyReportJobとの互換性維持
#
# 使用例:
#   target_month = Date.current.beginning_of_month
#   summary = InventoryReportService.monthly_summary(target_month)
#   analysis = InventoryReportService.detailed_analysis(target_month)
# ============================================================================

class InventoryReportService
  # ============================================================================
  # エラークラス
  # ============================================================================
  class DataNotFoundError < StandardError; end
  class CalculationError < StandardError; end

  # ============================================================================
  # 定数定義
  # ============================================================================
  LOW_STOCK_THRESHOLD = 10
  HIGH_VALUE_THRESHOLD = 10_000
  CRITICAL_STOCK_THRESHOLD = 5

  class << self
    # ============================================================================
    # 公開API - 月次サマリー
    # ============================================================================

    # 月次在庫サマリーの生成
    # @param target_month [Date] 対象月（月初日）
    # @param options [Hash] オプション設定
    # @return [Hash] 在庫サマリーデータ
    def monthly_summary(target_month, options = {})
      validate_target_month!(target_month)

      Rails.logger.info "[InventoryReportService] Generating monthly summary for #{target_month}"

      begin
        {
          target_date: target_month,
          total_items: calculate_total_items,
          total_value: calculate_total_value,
          low_stock_items: calculate_low_stock_items,
          critical_stock_items: calculate_critical_stock_items,
          high_value_items: calculate_high_value_items,
          average_quantity: calculate_average_quantity,
          categories_breakdown: calculate_categories_breakdown,
          monthly_changes: calculate_monthly_changes(target_month),
          inventory_health_score: calculate_inventory_health_score
        }
      rescue => e
        Rails.logger.error "[InventoryReportService] Error generating monthly summary: #{e.message}"
        raise CalculationError, "月次サマリー生成エラー: #{e.message}"
      end
    end

    # 詳細分析データの生成
    # @param target_month [Date] 対象月
    # @return [Hash] 詳細分析データ
    def detailed_analysis(target_month)
      validate_target_month!(target_month)

      {
        value_distribution: calculate_value_distribution,
        quantity_distribution: calculate_quantity_distribution,
        price_ranges: calculate_price_ranges,
        stock_movement_patterns: analyze_stock_movement_patterns(target_month),
        seasonal_trends: analyze_seasonal_trends(target_month),
        optimization_recommendations: generate_optimization_recommendations
      }
    end

    # 在庫効率分析
    # @param target_month [Date] 対象月
    # @return [Hash] 効率分析データ
    def efficiency_analysis(target_month)
      {
        turnover_rate: calculate_inventory_turnover_rate(target_month),
        holding_cost_efficiency: calculate_holding_cost_efficiency,
        space_utilization: calculate_space_utilization,
        carrying_cost_ratio: calculate_carrying_cost_ratio,
        stockout_risk: calculate_stockout_risk
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
    # 基本計算メソッド
    # ============================================================================

    def calculate_total_items
      # TODO: 🔴 Phase 1（緊急）- Counter Cache活用による最適化
      # 優先度: 高（パフォーマンス改善）
      # 実装内容: Inventory.countの代わりにcounter_cacheを活用
      # 横展開確認: 他の集計処理でも同様の最適化適用
      Inventory.count
    end

    def calculate_total_value
      # TODO: 🟠 Phase 2（重要）- 在庫評価方法の選択機能
      # 優先度: 中（業務要件対応）
      # 実装内容: FIFO、LIFO、平均原価法の選択
      # 理由: 会計基準・税務対応のため
      Inventory.sum("quantity * price")
    end

    def calculate_low_stock_items
      Inventory.joins(:batches)
               .where("batches.quantity <= ?", LOW_STOCK_THRESHOLD)
               .distinct
               .count
    end

    def calculate_critical_stock_items
      Inventory.joins(:batches)
               .where("batches.quantity <= ?", CRITICAL_STOCK_THRESHOLD)
               .distinct
               .count
    end

    def calculate_high_value_items
      Inventory.where("price >= ?", HIGH_VALUE_THRESHOLD).count
    end

    def calculate_average_quantity
      Inventory.average(:quantity)&.round(2) || 0
    end

    # ============================================================================
    # 高度な分析メソッド
    # ============================================================================

    def calculate_categories_breakdown
      # TODO: 🟡 Phase 2（中）- カテゴリ機能実装後の拡張
      # 優先度: 中（機能拡張）
      # 実装内容: Category モデル実装後の詳細分類
      # 現在は暫定実装
      {
        "未分類" => Inventory.count,
        "高価格帯" => Inventory.where("price >= ?", HIGH_VALUE_THRESHOLD).count,
        "中価格帯" => Inventory.where("price BETWEEN ? AND ?", 1000, HIGH_VALUE_THRESHOLD - 1).count,
        "低価格帯" => Inventory.where("price < ?", 1000).count
      }
    end

    def calculate_monthly_changes(target_month)
      previous_month = target_month - 1.month

      # TODO: 🟠 Phase 2（重要）- 月次比較の精度向上
      # 優先度: 高（分析精度向上）
      # 実装内容:
      #   - 月末時点のスナップショット機能
      #   - 正確な前月比計算
      #   - 季節調整機能
      # 横展開確認: 他の時系列分析での同様実装

      current_total = calculate_total_items
      # 暫定実装: 前月データの推定
      previous_total = current_total * 0.95 # 仮の増加率

      {
        total_items_change: current_total - previous_total,
        total_items_change_percent: calculate_percentage_change(previous_total, current_total),
        value_change: 0, # TODO: 実装
        new_items: 0,    # TODO: 実装
        removed_items: 0 # TODO: 実装
      }
    end

    def calculate_inventory_health_score
      # 在庫健全性スコア（100点満点）
      scores = []

      # 在庫バランススコア（40点）
      low_stock_ratio = calculate_low_stock_items.to_f / calculate_total_items
      balance_score = [ 40 - (low_stock_ratio * 40), 0 ].max
      scores << balance_score

      # 価値効率スコア（30点）
      high_value_ratio = calculate_high_value_items.to_f / calculate_total_items
      value_score = [ high_value_ratio * 30, 30 ].min
      scores << value_score

      # 回転効率スコア（30点）
      # TODO: 実装（売上データ必要）
      turnover_score = 20 # 暫定値
      scores << turnover_score

      scores.sum.round(1)
    end

    # ============================================================================
    # 分析メソッド
    # ============================================================================

    def calculate_value_distribution
      # 価値分布の分析
      ranges = [
        { min: 0, max: 1000, label: "低価格帯" },
        { min: 1000, max: 5000, label: "中価格帯" },
        { min: 5000, max: 10000, label: "高価格帯" },
        { min: 10000, max: Float::INFINITY, label: "超高価格帯" }
      ]

      ranges.map do |range|
        count = if range[:max] == Float::INFINITY
          Inventory.where("price >= ?", range[:min]).count
        else
          Inventory.where("price BETWEEN ? AND ?", range[:min], range[:max] - 1).count
        end

        {
          label: range[:label],
          min: range[:min],
          max: range[:max] == Float::INFINITY ? nil : range[:max],
          count: count,
          percentage: (count.to_f / calculate_total_items * 100).round(2)
        }
      end
    end

    def calculate_quantity_distribution
      # 数量分布の分析
      [
        { range: "0-10", count: Inventory.where("quantity BETWEEN ? AND ?", 0, 10).count },
        { range: "11-50", count: Inventory.where("quantity BETWEEN ? AND ?", 11, 50).count },
        { range: "51-100", count: Inventory.where("quantity BETWEEN ? AND ?", 51, 100).count },
        { range: "101+", count: Inventory.where("quantity > ?", 100).count }
      ]
    end

    def calculate_price_ranges
      {
        min_price: Inventory.minimum(:price) || 0,
        max_price: Inventory.maximum(:price) || 0,
        median_price: calculate_median_price,
        mode_price: calculate_mode_price
      }
    end

    def analyze_stock_movement_patterns(target_month)
      # TODO: 🟡 Phase 3（推奨）- InventoryLogを使った詳細分析
      # 優先度: 中（高度分析機能）
      # 実装内容:
      #   - 入庫・出庫パターンの分析
      #   - 季節性の検出
      #   - 異常パターンの識別
      {
        most_active_items: [], # TODO: 実装
        least_active_items: [], # TODO: 実装
        movement_frequency: {}, # TODO: 実装
        peak_activity_periods: [] # TODO: 実装
      }
    end

    def analyze_seasonal_trends(target_month)
      # TODO: 🟢 Phase 3（推奨）- 季節性分析の実装
      # 優先度: 低（高度分析機能）
      # 実装内容: 過去データの季節性分析
      {
        seasonal_index: 1.0, # 暫定値
        trend_direction: "stable", # 暫定値
        volatility_score: 0.1 # 暫定値
      }
    end

    def generate_optimization_recommendations
      recommendations = []

      # 低在庫アラート
      if calculate_low_stock_items > 0
        recommendations << {
          type: "warning",
          priority: "high",
          message: "#{calculate_low_stock_items}件のアイテムが低在庫状態です。発注検討をお勧めします。"
        }
      end

      # 高価値アイテムの管理
      if calculate_high_value_items > calculate_total_items * 0.1
        recommendations << {
          type: "info",
          priority: "medium",
          message: "高価値アイテムが全体の10%を超えています。セキュリティ管理の強化を検討してください。"
        }
      end

      # TODO: 🟡 Phase 2（中）- AI/機械学習による推奨機能
      # 優先度: 中（付加価値向上）
      # 実装内容:
      #   - 需要予測に基づく発注推奨
      #   - 異常検知による在庫調整提案
      #   - コスト最適化の提案

      recommendations
    end

    # ============================================================================
    # ヘルパーメソッド
    # ============================================================================

    def calculate_percentage_change(old_value, new_value)
      return 0 if old_value.zero?
      ((new_value - old_value) / old_value * 100).round(2)
    end

    def calculate_median_price
      prices = Inventory.pluck(:price).sort
      return 0 if prices.empty?

      mid = prices.length / 2
      if prices.length.odd?
        prices[mid]
      else
        (prices[mid - 1] + prices[mid]) / 2.0
      end
    end

    def calculate_mode_price
      price_counts = Inventory.group(:price).count
      return 0 if price_counts.empty?
      price_counts.max_by { |price, count| count }&.first || 0
    end

    # 将来の拡張メソッド（売上データ必要）
    def calculate_inventory_turnover_rate(target_month)
      # TODO: 🔴 Phase 2（緊急）- 売上データ連携後の実装
      # 計算式: 売上原価 / 平均在庫金額
      0 # 暫定値
    end

    def calculate_holding_cost_efficiency
      # TODO: 保管コスト効率の計算
      0 # 暫定値
    end

    def calculate_space_utilization
      # TODO: 倉庫スペース使用率の計算
      0 # 暫定値
    end

    def calculate_carrying_cost_ratio
      # TODO: 運搬コスト比率の計算
      0 # 暫定値
    end

    def calculate_stockout_risk
      # TODO: 在庫切れリスクの計算
      0 # 暫定値
    end
  end
end
