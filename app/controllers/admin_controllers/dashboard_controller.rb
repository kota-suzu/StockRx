# frozen_string_literal: true

module AdminControllers
  # 管理者ダッシュボード画面用コントローラ
  class DashboardController < BaseController
    # CLAUDE.md準拠: セキュリティ機能最適化
    # メタ認知: ダッシュボードは統計表示のみで機密データ操作はないため監査不要
    # 横展開: 他の表示専用コントローラーでも同様の考慮が必要
    skip_around_action :audit_sensitive_data_access

    def index
      # パフォーマンス最適化: 統計データを効率的に事前計算
      calculate_dashboard_statistics
      load_recent_activities
    end

    private

    def calculate_dashboard_statistics
      # Counter Cacheを活用したN+1クエリ最適化（CLAUDE.md準拠）
      @stats = {
        total_inventories: Inventory.count,
        low_stock_count: Inventory.low_stock.count,
        total_inventory_value: calculate_total_inventory_value,
        today_operations: today_operations_count,
        active_inventories: Inventory.where(status: "active").count,
        archived_inventories: Inventory.where(status: "archived").count,
        weekly_operations: weekly_operations_count,
        monthly_operations: monthly_operations_count,
        average_inventory_value: calculate_average_inventory_value,
        total_batches: calculate_total_batches,
        expiring_batches: calculate_expiring_batches,
        expired_batches: calculate_expired_batches,
        low_stock_items: load_low_stock_items
      }
    end

    def load_recent_activities
      # includes最適化で関連データを事前ロード
      @recent_logs = InventoryLog.includes(:inventory)
                                 .order(created_at: :desc)
                                 .limit(5)
    end

    def calculate_total_inventory_value
      # SQL集約関数でパフォーマンス最適化
      Inventory.sum("quantity * price")
    end

    def today_operations_count
      # 日時範囲でのカウント最適化
      InventoryLog.where(
        created_at: Date.current.beginning_of_day..Date.current.end_of_day
      ).count
    end

    def weekly_operations_count
      # 週間操作数（過去7日間）
      InventoryLog.where(
        created_at: 7.days.ago.beginning_of_day..Date.current.end_of_day
      ).count
    end

    def monthly_operations_count
      # 月間操作数（過去30日間）
      InventoryLog.where(
        created_at: 30.days.ago.beginning_of_day..Date.current.end_of_day
      ).count
    end

    def calculate_average_inventory_value
      # 平均在庫価値（SQL集約関数でパフォーマンス最適化）
      total_count = Inventory.count
      return 0 if total_count.zero?

      (calculate_total_inventory_value.to_f / total_count).round
    end

    def calculate_total_batches
      # 全バッチ数（Counter Cacheを活用）
      Inventory.sum(:batches_count)
    end

    def calculate_expiring_batches
      # 期限間近バッチ数（30日以内に期限切れ）
      Batch.joins(:inventory)
           .where("expires_on BETWEEN ? AND ?", Date.current, 30.days.from_now)
           .count
    end

    def calculate_expired_batches
      # 期限切れバッチ数
      Batch.joins(:inventory)
           .where("expires_on < ?", Date.current)
           .count
    end

    def load_low_stock_items
      # 低在庫商品の詳細情報を取得
      Inventory.low_stock.map do |item|
        {
          id: item.id,
          name: item.name,
          quantity: item.quantity,
          price: item.price
        }
      end
    end

    # TODO: 🟡 Phase 2（中）- 高度な統計機能実装
    # 優先度: 中（基本機能は動作確認済み）
    # 実装内容: 期限切れ商品アラート、売上予測レポート、システム監視
    # 理由: ダッシュボードの情報価値向上
    # 期待効果: 管理者の意思決定支援、予防的在庫管理
    # 工数見積: 1-2週間
    # 依存関係: Order、Expiration等のモデル実装

    # TODO: 🟢 Phase 3（推奨）- コントローラディレクトリ構造の横展開確認
    # 優先度: 低（現在の構造は正常動作中）
    # 実装内容: 他のAdminControllersでも同様の最適化パターン適用
    # 理由: 一貫したパフォーマンス最適化とコード品質維持
    # 期待効果: システム全体のレスポンス時間向上
    # 工数見積: 各コントローラー半日
    # 依存関係: なし
  end
end
