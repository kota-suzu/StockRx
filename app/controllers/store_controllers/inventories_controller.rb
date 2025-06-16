# frozen_string_literal: true

module StoreControllers
  # 店舗在庫管理コントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # 店舗スコープでの在庫閲覧・管理
  # ============================================
  class InventoriesController < BaseController
    before_action :set_inventory, only: [ :show, :request_transfer ]

    # ============================================
    # アクション
    # ============================================

    # 在庫一覧
    def index
      @q = current_store.store_inventories
                       .joins(:inventory)
                       .includes(:inventory, :batches)
                       .ransack(params[:q])

      @store_inventories = @q.result
                            .order(sort_column => sort_direction)
                            .page(params[:page])
                            .per(per_page)

      # フィルタリング用のデータ
      load_filter_data

      # 統計情報
      load_statistics
    end

    # 在庫詳細
    def show
      @store_inventory = current_store.store_inventories
                                     .includes(:inventory, :batches)
                                     .find_by!(inventory: @inventory)

      # バッチ情報
      @batches = @store_inventory.batches
                                .order(expiration_date: :asc)
                                .page(params[:batch_page])

      # 在庫履歴
      @inventory_logs = @inventory.inventory_logs
                                 .where(store_id: current_store.id)
                                 .includes(:admin)
                                 .order(created_at: :desc)
                                 .limit(20)

      # 移動履歴
      @transfer_history = load_transfer_history
    end

    # 店舗間移動申請
    def request_transfer
      @store_inventory = current_store.store_inventories.find_by!(inventory: @inventory)
      @transfer = current_store.outgoing_transfers.build(
        inventory: @inventory,
        requested_by: current_store_user
      )

      # 他店舗の在庫状況
      @other_stores_inventory = StoreInventory.where(inventory: @inventory)
                                             .where.not(store: current_store)
                                             .includes(:store)
                                             .order("stores.name")
    end

    private

    # ============================================
    # 共通処理
    # ============================================

    def set_inventory
      @inventory = Inventory.find(params[:id])
    end

    # ============================================
    # データ読み込み
    # ============================================

    # フィルタリング用データ
    def load_filter_data
      @categories = current_store.inventories
                                .distinct
                                .pluck(:category)
                                .compact
                                .sort

      @manufacturers = current_store.inventories
                                   .distinct
                                   .pluck(:manufacturer)
                                   .compact
                                   .sort

      @stock_levels = [
        [ "在庫切れ", "out_of_stock" ],
        [ "低在庫", "low_stock" ],
        [ "適正在庫", "normal_stock" ],
        [ "過剰在庫", "excess_stock" ]
      ]
    end

    # 統計情報の読み込み
    def load_statistics
      @statistics = {
        total_items: @q.result.count,
        total_quantity: @q.result.sum(:quantity),
        total_value: calculate_total_value(@q.result),
        low_stock_percentage: calculate_low_stock_percentage
      }
    end

    # 合計金額の計算
    def calculate_total_value(store_inventories)
      store_inventories.joins(:inventory)
                      .sum("store_inventories.quantity * inventories.price")
    end

    # 低在庫率の計算
    def calculate_low_stock_percentage
      total = @q.result.count
      return 0 if total.zero?

      low_stock = @q.result.where("quantity <= safety_stock_level").count
      ((low_stock.to_f / total) * 100).round(1)
    end

    # 移動履歴の読み込み
    def load_transfer_history
      InterStoreTransfer.where(
        "(source_store_id = :store_id OR destination_store_id = :store_id) AND inventory_id = :inventory_id",
        store_id: current_store.id,
        inventory_id: @inventory.id
      ).includes(:source_store, :destination_store, :requested_by, :approved_by)
       .order(created_at: :desc)
       .limit(10)
    end

    # ============================================
    # ソート設定
    # ============================================

    def sort_column
      %w[inventories.name inventories.sku quantity safety_stock_level].include?(params[:sort]) ? params[:sort] : "inventories.name"
    end

    def sort_direction
      %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
    end

    # ============================================
    # ビューヘルパー
    # ============================================

    # 在庫レベルのバッジ
    helper_method :stock_level_badge
    def stock_level_badge(store_inventory)
      if store_inventory.quantity == 0
        { text: "在庫切れ", class: "badge bg-danger" }
      elsif store_inventory.quantity <= store_inventory.safety_stock_level
        { text: "低在庫", class: "badge bg-warning text-dark" }
      elsif store_inventory.quantity > store_inventory.safety_stock_level * 2
        { text: "過剰在庫", class: "badge bg-info" }
      else
        { text: "適正", class: "badge bg-success" }
      end
    end

    # 在庫回転日数
    helper_method :turnover_days
    def turnover_days(store_inventory)
      # TODO: Phase 4 - 実際の販売データから計算
      # 仮実装
      return "---" if store_inventory.quantity.zero?

      daily_usage = 5 # 仮の日次使用量
      (store_inventory.quantity / daily_usage.to_f).round
    end

    # バッチステータス
    helper_method :batch_status_badge
    def batch_status_badge(batch)
      days_until_expiry = (batch.expiration_date - Date.current).to_i

      if days_until_expiry < 0
        { text: "期限切れ", class: "badge bg-danger" }
      elsif days_until_expiry <= 30
        { text: "#{days_until_expiry}日", class: "badge bg-warning text-dark" }
      elsif days_until_expiry <= 90
        { text: "#{days_until_expiry}日", class: "badge bg-info" }
      else
        { text: "良好", class: "badge bg-success" }
      end
    end
  end
end

# ============================================
# TODO: Phase 4以降の拡張予定
# ============================================
# 1. 🔴 在庫調整機能
#    - 棚卸し機能
#    - 廃棄処理
#    - 調整履歴
#
# 2. 🟡 発注提案
#    - 需要予測に基づく発注量提案
#    - 自動発注設定
#
# 3. 🟢 バーコードスキャン
#    - モバイルアプリ連携
#    - リアルタイム在庫更新
