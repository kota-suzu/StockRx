# frozen_string_literal: true

module StoreControllers
  # 店舗ダッシュボードコントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # 店舗スタッフ用のメインダッシュボード
  # ============================================
  class DashboardController < BaseController
    # アクセス制御（全スタッフアクセス可能）
    # BaseControllerで認証済み

    # ============================================
    # アクション
    # ============================================

    def index
      # 店舗の基本統計情報
      load_store_statistics

      # 在庫アラート情報
      load_inventory_alerts

      # 店舗間移動情報
      load_transfer_summary

      # 最近のアクティビティ
      load_recent_activities

      # グラフ用データ
      load_chart_data
    end

    private

    # ============================================
    # データ読み込み
    # ============================================

    # 店舗統計情報の読み込み
    def load_store_statistics
      @statistics = {
        total_items: current_store.store_inventories.count,
        total_quantity: current_store.store_inventories.sum(:quantity),
        total_value: current_store.total_inventory_value,
        low_stock_items: current_store.low_stock_items_count,
        out_of_stock_items: current_store.out_of_stock_items_count,
        pending_transfers_in: current_store.incoming_transfers.pending.count,
        pending_transfers_out: current_store.outgoing_transfers.pending.count
      }
    end

    # 在庫アラート情報の読み込み
    def load_inventory_alerts
      @low_stock_items = current_store.store_inventories
                                     .joins(:inventory)
                                     .where("store_inventories.quantity <= store_inventories.safety_stock_level")
                                     .where("store_inventories.quantity > 0")
                                     .includes(:inventory)
                                     .order("(store_inventories.quantity::float / NULLIF(store_inventories.safety_stock_level, 0)) ASC")
                                     .limit(10)

      @out_of_stock_items = current_store.store_inventories
                                         .joins(:inventory)
                                         .where(quantity: 0)
                                         .includes(:inventory)
                                         .order(updated_at: :desc)
                                         .limit(10)

      @expiring_items = current_store.store_inventories
                                     .joins(:inventory, :batches)
                                     .where("batches.expiration_date <= ?", 30.days.from_now)
                                     .where("batches.expiration_date >= ?", Date.current)
                                     .select("store_inventories.*, batches.expiration_date, batches.lot_number")
                                     .includes(:inventory)
                                     .order("batches.expiration_date ASC")
                                     .limit(10)
    end

    # 店舗間移動サマリーの読み込み
    def load_transfer_summary
      @pending_incoming = current_store.incoming_transfers
                                      .pending
                                      .includes(:source_store, :inventory)
                                      .order(requested_at: :desc)
                                      .limit(5)

      @pending_outgoing = current_store.outgoing_transfers
                                      .pending
                                      .includes(:destination_store, :inventory)
                                      .order(requested_at: :desc)
                                      .limit(5)

      @recent_completed = InterStoreTransfer.where(
        "(source_store_id = :store_id OR destination_store_id = :store_id) AND status = 'completed'",
        store_id: current_store.id
      ).includes(:source_store, :destination_store, :inventory)
       .order(completed_at: :desc)
       .limit(5)
    end

    # 最近のアクティビティ
    def load_recent_activities
      # TODO: Phase 4 - アクティビティログの実装
      @recent_activities = []

      # 仮実装：最近の在庫変動
      @recent_inventory_changes = InventoryLog.joins(inventory: :store_inventories)
                                             .where(store_inventories: { store_id: current_store.id })
                                             .includes(:inventory, :admin)
                                             .order(created_at: :desc)
                                             .limit(10)
    end

    # グラフ用データの読み込み
    def load_chart_data
      # 過去7日間の在庫推移
      @inventory_trend_data = prepare_inventory_trend_data

      # カテゴリ別在庫構成
      @category_distribution = prepare_category_distribution

      # 店舗間移動トレンド
      @transfer_trend_data = prepare_transfer_trend_data
    end

    # ============================================
    # グラフデータ準備
    # ============================================

    # 在庫推移データの準備
    def prepare_inventory_trend_data
      dates = (6.days.ago.to_date..Date.current).to_a

      trend_data = dates.map do |date|
        # その日の終わりの在庫数を計算
        quantity = calculate_inventory_on_date(date)

        {
          date: date.strftime("%m/%d"),
          quantity: quantity
        }
      end

      trend_data.to_json
    end

    # 特定日の在庫数計算
    def calculate_inventory_on_date(date)
      # 簡易実装：現在の在庫数を返す
      # TODO: Phase 4 - 履歴データからの正確な計算
      current_store.store_inventories.sum(:quantity)
    end

    # カテゴリ別在庫構成の準備
    def prepare_category_distribution
      categories = current_store.inventories
                               .group(:category)
                               .joins(:store_inventories)
                               .where(store_inventories: { store_id: current_store.id })
                               .sum("store_inventories.quantity")

      categories.map do |category, quantity|
        {
          name: category || "未分類",
          value: quantity
        }
      end.to_json
    end

    # 店舗間移動トレンドの準備
    def prepare_transfer_trend_data
      dates = (6.days.ago.to_date..Date.current).to_a

      trend_data = dates.map do |date|
        incoming = current_store.incoming_transfers
                               .where(requested_at: date.beginning_of_day..date.end_of_day)
                               .count

        outgoing = current_store.outgoing_transfers
                               .where(requested_at: date.beginning_of_day..date.end_of_day)
                               .count

        {
          date: date.strftime("%m/%d"),
          incoming: incoming,
          outgoing: outgoing
        }
      end

      trend_data.to_json
    end

    # ============================================
    # ヘルパーメソッド
    # ============================================

    # 在庫レベルのステータスクラス
    helper_method :inventory_level_class
    def inventory_level_class(store_inventory)
      ratio = store_inventory.quantity.to_f / store_inventory.safety_stock_level.to_f

      if store_inventory.quantity == 0
        "text-danger"
      elsif ratio <= 0.5
        "text-warning"
      elsif ratio <= 1.0
        "text-info"
      else
        "text-success"
      end
    end

    # 期限切れまでの日数によるクラス
    helper_method :expiration_class
    def expiration_class(expiration_date)
      days_until = (expiration_date - Date.current).to_i

      if days_until <= 7
        "text-danger"
      elsif days_until <= 14
        "text-warning"
      else
        "text-info"
      end
    end
  end
end

# ============================================
# TODO: Phase 4以降の拡張予定
# ============================================
# 1. 🔴 リアルタイム更新
#    - ActionCableによる在庫変動の即時反映
#    - 移動申請の通知
#
# 2. 🟡 カスタマイズ可能なウィジェット
#    - ドラッグ&ドロップでの配置変更
#    - 表示項目の選択
#
# 3. 🟢 エクスポート機能
#    - ダッシュボードデータのPDF/Excel出力
#    - 定期レポートの自動生成
