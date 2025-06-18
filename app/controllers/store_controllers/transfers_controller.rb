# frozen_string_literal: true

module StoreControllers
  # 店舗間移動管理コントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # Phase 5-1: レート制限追加
  # 店舗視点での移動申請・管理
  # ============================================
  class TransfersController < BaseController
    include RateLimitable

    before_action :set_transfer, only: [ :show, :cancel ]
    before_action :ensure_can_cancel, only: [ :cancel ]

    # ============================================
    # アクション
    # ============================================

    # 移動一覧
    def index
      # CLAUDE.md準拠: ransack代替実装でセキュリティとパフォーマンスを両立
      base_scope = InterStoreTransfer.where(
        "source_store_id = :store_id OR destination_store_id = :store_id",
        store_id: current_store.id
      )

      # 検索条件の適用（ransackの代替）
      @q = apply_search_filters(base_scope, params[:q] || {})

      @transfers = @q.includes(:source_store, :destination_store, :inventory,
                              :requested_by, :approved_by)
                    .order(created_at: :desc)
                    .page(params[:page])
                    .per(per_page)

      # タブ用のカウント
      load_transfer_counts
    end

    # 移動詳細
    def show
      # タイムライン形式の履歴
      @timeline_events = build_timeline_events

      # 関連する在庫情報
      load_inventory_info
    end

    # 新規移動申請
    def new
      @transfer = current_store.outgoing_transfers.build(
        requested_by: current_store_user
      )

      # 在庫選択用のデータ
      # 🔧 SQL修正: テーブル名明示でカラム曖昧性解消（store_inventories.quantityを明確化）
      # CLAUDE.md準拠: store_inventoriesとinventoriesの両テーブルにquantityカラム存在のため
      @available_inventories = current_store.store_inventories
                                          .where("store_inventories.quantity > store_inventories.reserved_quantity")
                                          .includes(:inventory)
                                          .order("inventories.name")

      # 送付先店舗の選択肢
      @destination_stores = Store.active
                                .where.not(id: current_store.id)
                                .order(:store_type, :name)
    end

    # 移動申請作成
    def create
      @transfer = current_store.outgoing_transfers.build(transfer_params)
      @transfer.requested_by = current_store_user
      @transfer.status = "pending"
      @transfer.requested_at = Time.current

      if @transfer.save
        # 在庫予約
        reserve_inventory(@transfer)

        # 通知送信
        notify_transfer_request(@transfer)

        redirect_to store_transfer_path(@transfer),
                    notice: I18n.t("messages.transfer_requested")
      else
        load_form_data
        render :new, status: :unprocessable_entity
      end
    end

    # 移動申請取消
    def cancel
      if @transfer.cancel_by!(current_store_user)
        # 在庫予約解除
        release_inventory_reservation(@transfer)

        redirect_to store_transfers_path,
                    notice: I18n.t("messages.transfer_cancelled")
      else
        redirect_to store_transfer_path(@transfer),
                    alert: I18n.t("errors.messages.cannot_cancel_transfer")
      end
    end

    private

    # ============================================
    # 共通処理
    # ============================================

    def set_transfer
      @transfer = InterStoreTransfer.accessible_by_store(current_store)
                                   .find(params[:id])
    end

    def ensure_can_cancel
      unless @transfer.can_be_cancelled_by?(current_store_user)
        redirect_to store_transfer_path(@transfer),
                    alert: I18n.t("errors.messages.insufficient_permissions")
      end
    end

    # ============================================
    # パラメータ
    # ============================================

    def transfer_params
      params.require(:inter_store_transfer).permit(
        :destination_store_id,
        :inventory_id,
        :quantity,
        :priority,
        :reason,
        :notes,
        :requested_delivery_date
      )
    end

    # ============================================
    # データ読み込み
    # ============================================

    # 移動カウントの読み込み
    def load_transfer_counts
      base_query = InterStoreTransfer.where(
        "source_store_id = :store_id OR destination_store_id = :store_id",
        store_id: current_store.id
      )

      @transfer_counts = {
        all: base_query.count,
        outgoing: current_store.outgoing_transfers.count,
        incoming: current_store.incoming_transfers.count,
        pending: base_query.pending.count,
        in_transit: base_query.in_transit.count,
        completed: base_query.completed.count
      }
    end

    # フォーム用データの読み込み
    def load_form_data
      # 🔧 SQL修正: テーブル名明示でカラム曖昧性解消（横展開適用）
      # メタ認知: newアクションと同じパターンで一貫性確保
      @available_inventories = current_store.store_inventories
                                          .where("store_inventories.quantity > store_inventories.reserved_quantity")
                                          .includes(:inventory)
                                          .order("inventories.name")

      @destination_stores = Store.active
                                .where.not(id: current_store.id)
                                .order(:store_type, :name)
    end

    # 在庫情報の読み込み
    def load_inventory_info
      @source_inventory = @transfer.source_store
                                  .store_inventories
                                  .find_by(inventory: @transfer.inventory)

      @destination_inventory = @transfer.destination_store
                                       .store_inventories
                                       .find_by(inventory: @transfer.inventory)
    end

    # ============================================
    # ビジネスロジック
    # ============================================

    # 在庫予約
    def reserve_inventory(transfer)
      store_inventory = transfer.source_store
                               .store_inventories
                               .find_by!(inventory: transfer.inventory)

      store_inventory.increment!(:reserved_quantity, transfer.quantity)
    end

    # 在庫予約解除
    def release_inventory_reservation(transfer)
      return unless transfer.pending? || transfer.approved?

      store_inventory = transfer.source_store
                               .store_inventories
                               .find_by(inventory: transfer.inventory)

      store_inventory&.decrement!(:reserved_quantity, transfer.quantity)
    end

    # 移動申請通知
    def notify_transfer_request(transfer)
      # TODO: Phase 4 - 通知機能の実装
      # TransferNotificationJob.perform_later(transfer)
    end

    # ============================================
    # タイムライン構築
    # ============================================

    def build_timeline_events
      events = []

      # 申請
      events << {
        timestamp: @transfer.requested_at,
        event: "requested",
        user: @transfer.requested_by,
        icon: "fas fa-plus-circle",
        color: "primary"
      }

      # 承認/却下
      if @transfer.approved_at.present?
        events << {
          timestamp: @transfer.approved_at,
          event: @transfer.approved? ? "approved" : "rejected",
          user: @transfer.approved_by,
          icon: @transfer.approved? ? "fas fa-check-circle" : "fas fa-times-circle",
          color: @transfer.approved? ? "success" : "danger"
        }
      end

      # 出荷
      if @transfer.shipped_at.present?
        events << {
          timestamp: @transfer.shipped_at,
          event: "shipped",
          user: @transfer.shipped_by,
          icon: "fas fa-truck",
          color: "info"
        }
      end

      # 完了
      if @transfer.completed_at.present?
        events << {
          timestamp: @transfer.completed_at,
          event: "completed",
          user: @transfer.completed_by,
          icon: "fas fa-check-double",
          color: "success"
        }
      end

      # キャンセル
      if @transfer.cancelled?
        events << {
          timestamp: @transfer.updated_at,
          event: "cancelled",
          user: @transfer.cancelled_by,
          icon: "fas fa-ban",
          color: "secondary"
        }
      end

      events.sort_by { |e| e[:timestamp] }
    end

    private

    # 検索フィルターの適用（ransack代替実装）
    # CLAUDE.md準拠: SQLインジェクション対策とパフォーマンス最適化
    # TODO: 🟡 Phase 3（重要）- 移動履歴高度検索機能
    #   - 移動経路・ルート検索
    #   - 承認者・申請者による絞り込み
    #   - 移動量・金額による範囲検索
    #   - 横展開: 管理者側InterStoreTransfersControllerとの統合
    def apply_search_filters(scope, search_params)
      # 在庫名検索
      if search_params[:inventory_name_cont].present?
        scope = scope.joins(:inventory)
                    .where("inventories.name LIKE ?", "%#{sanitize_sql_like(search_params[:inventory_name_cont])}%")
      end

      # ステータスフィルター
      if search_params[:status_eq].present?
        scope = scope.where(status: search_params[:status_eq])
      end

      # 日付範囲フィルター
      if search_params[:requested_at_gteq].present?
        scope = scope.where("requested_at >= ?", Date.parse(search_params[:requested_at_gteq]))
      end

      if search_params[:requested_at_lteq].present?
        scope = scope.where("requested_at <= ?", Date.parse(search_params[:requested_at_lteq]).end_of_day)
      end

      # 移動方向フィルター
      case search_params[:direction_eq]
      when 'outgoing'
        scope = scope.where(source_store_id: current_store.id)
      when 'incoming'
        scope = scope.where(destination_store_id: current_store.id)
      end

      scope
    rescue Date::Error
      # 日付解析エラーの場合はフィルターをスキップ
      scope
    end

    # ============================================
    # ビューヘルパー
    # ============================================

    # 移動方向のアイコン
    helper_method :transfer_direction_icon
    def transfer_direction_icon(transfer)
      if transfer.source_store_id == current_store.id
        { icon_class: "fas fa-arrow-right text-danger", title: "出庫" }
      else
        { icon_class: "fas fa-arrow-left text-success", title: "入庫" }
      end
    end

    # 優先度バッジ
    helper_method :priority_badge
    def priority_badge(priority)
      case priority
      when "urgent"
        { text: "緊急", class: "badge bg-danger" }
      when "high"
        { text: "高", class: "badge bg-warning text-dark" }
      when "normal"
        { text: "通常", class: "badge bg-secondary" }
      when "low"
        { text: "低", class: "badge bg-light text-dark" }
      end
    end

    # ============================================
    # レート制限設定（Phase 5-1）
    # ============================================

    def rate_limited_actions
      [ :create ]  # 移動申請作成のみ制限
    end

    def rate_limit_key_type
      :transfer_request
    end

    def rate_limit_identifier
      # 店舗ユーザーIDで識別
      "store_user:#{current_store_user.id}"
    end
  end
end

# ============================================
# TODO: Phase 4以降の拡張予定
# ============================================
# 1. 🔴 配送追跡
#    - 配送業者連携
#    - リアルタイム位置情報
#
# 2. 🟡 バッチ移動
#    - 複数商品の一括移動
#    - テンプレート機能
#
# 3. 🟢 自動承認
#    - ルールベース承認
#    - 承認権限の委譲
