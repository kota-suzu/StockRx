# frozen_string_literal: true

# 在庫移動サービス
# ============================================
# 責務: 店舗間在庫移動の処理とビジネスロジック
# 分離元: StoreControllers::InventoriesController
# ============================================
class InventoryTransferService
  include ActiveModel::Model

  # Phase 1: 緊急分離 - 移動処理ロジックの専用サービス化
  # メタ認知: 複雑な移動処理を独立させ、テスト容易性向上

  def initialize(current_user: nil)
    @current_user = current_user
  end

  # 移動申請の作成
  def create_transfer_request(from_store:, inventory:, transfer_params:)
    to_store_id = transfer_params[:to_store_id]
    quantity = transfer_params[:quantity].to_i
    reason = transfer_params[:reason] || "店舗間移動"

    # バリデーション
    validation_result = validate_transfer_request(
      from_store: from_store,
      to_store_id: to_store_id,
      inventory: inventory,
      quantity: quantity
    )

    return validation_result unless validation_result[:valid]

    # 移動申請の作成
    ActiveRecord::Base.transaction do
      transfer_request = create_transfer_request_record(
        from_store: from_store,
        to_store_id: to_store_id,
        inventory: inventory,
        quantity: quantity,
        reason: reason
      )

      # 移動元在庫の予約処理
      reserve_inventory_for_transfer(from_store, inventory, quantity)

      # 通知処理
      notify_transfer_request(transfer_request)

      {
        success: true,
        transfer_request: transfer_request,
        message: "移動申請が正常に作成されました"
      }
    end
  rescue ActiveRecord::RecordInvalid => e
    {
      success: false,
      errors: e.record.errors.full_messages,
      message: "移動申請の作成に失敗しました"
    }
  rescue StandardError => e
    Rails.logger.error("Transfer request creation failed: #{e.message}")
    {
      success: false,
      errors: [ e.message ],
      message: "システムエラーが発生しました"
    }
  end

  # 移動履歴の取得
  def fetch_transfer_history(store:, inventory:, limit: 10)
    # InterStoreTransferモデルが存在する場合の実装
    return [] unless defined?(InterStoreTransfer)

    InterStoreTransfer.where(
      "(from_store_id = ? OR to_store_id = ?) AND inventory_id = ?",
      store.id, store.id, inventory.id
    ).includes(
      :from_store, :to_store, :inventory, :created_by_admin
    ).order(created_at: :desc)
     .limit(limit)
  end

  # 移動可能な店舗リストの取得
  def available_target_stores(current_store:)
    Store.active
         .where.not(id: current_store.id)
         .order(:name)
  end

  private

  # 移動申請のバリデーション
  def validate_transfer_request(from_store:, to_store_id:, inventory:, quantity:)
    errors = []

    # 基本バリデーション
    if to_store_id.blank?
      errors << "移動先店舗を選択してください"
    elsif to_store_id.to_i == from_store.id
      errors << "同じ店舗への移動はできません"
    end

    if quantity <= 0
      errors << "移動数量は1以上を指定してください"
    end

    # 在庫確認
    store_inventory = from_store.store_inventories.find_by(inventory: inventory)
    if store_inventory.nil?
      errors << "指定された商品の在庫が存在しません"
    elsif store_inventory.quantity < quantity
      errors << "在庫不足です（現在在庫: #{store_inventory.quantity}）"
    end

    # 移動先店舗の存在確認
    to_store = Store.active.find_by(id: to_store_id)
    if to_store.nil?
      errors << "指定された移動先店舗が見つかりません"
    end

    {
      valid: errors.empty?,
      errors: errors,
      to_store: to_store,
      store_inventory: store_inventory
    }
  end

  # 移動申請レコードの作成
  def create_transfer_request_record(from_store:, to_store_id:, inventory:, quantity:, reason:)
    # InterStoreTransferモデルが存在する場合の実装
    return create_fallback_log(from_store, to_store_id, inventory, quantity, reason) unless defined?(InterStoreTransfer)

    InterStoreTransfer.create!(
      from_store: from_store,
      to_store_id: to_store_id,
      inventory: inventory,
      quantity: quantity,
      reason: reason,
      status: "pending",
      requested_by: @current_user,
      requested_at: Time.current
    )
  end

  # フォールバック用のログ作成
  def create_fallback_log(from_store, to_store_id, inventory, quantity, reason)
    # InventoryLogでの代替記録
    InventoryLog.create!(
      inventory: inventory,
      store: from_store,
      user: @current_user,
      action: "transfer_request",
      quantity_before: nil,
      quantity_after: nil,
      quantity_changed: -quantity,
      reason: reason,
      metadata: {
        transfer_type: "outbound_request",
        to_store_id: to_store_id,
        requested_quantity: quantity,
        status: "pending",
        timestamp: Time.current.iso8601
      }
    )
  end

  # 在庫の予約処理
  def reserve_inventory_for_transfer(store, inventory, quantity)
    store_inventory = store.store_inventories.find_by!(inventory: inventory)

    current_reserved = store_inventory.reserved_quantity || 0
    new_reserved = current_reserved + quantity

    store_inventory.update!(reserved_quantity: new_reserved)

    # 予約ログの記録
    InventoryLog.create!(
      inventory: inventory,
      store: store,
      user: @current_user,
      action: "reserve_for_transfer",
      quantity_before: current_reserved,
      quantity_after: new_reserved,
      quantity_changed: quantity,
      reason: "移動申請による予約",
      metadata: {
        reservation_type: "transfer_request",
        reserved_quantity: quantity,
        timestamp: Time.current.iso8601
      }
    )
  end

  # 移動申請の通知処理
  def notify_transfer_request(transfer_request)
    # 通知ロジックの実装（将来的にActionMailer等で実装）
    Rails.logger.info({
      event: "transfer_request_created",
      transfer_request_id: transfer_request.id,
      from_store_id: transfer_request.from_store.id,
      to_store_id: transfer_request.to_store_id,
      inventory_id: transfer_request.inventory.id,
      quantity: transfer_request.quantity,
      requested_by: @current_user&.email,
      timestamp: Time.current.iso8601
    }.to_json)

    # TODO: Phase 2実装予定
    # - 移動先店舗への通知メール
    # - 管理者への申請通知
    # - Slack/Teams等への通知連携
  end
end
