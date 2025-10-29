# frozen_string_literal: true

# 店舗在庫管理サービス
# ============================================
# 責務: 店舗在庫の基本操作とビジネスロジック
# 分離元: StoreControllers::InventoriesController
# ============================================
class StoreInventoryManagementService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Phase 1: 緊急分離 - コントローラーからビジネスロジック抽出
  # メタ認知: 単一責任原則適用により、テスト容易性とメンテナンス性向上

  def initialize(store:, current_user: nil)
    @store = store
    @current_user = current_user
  end

  # 在庫一覧の基本スコープを構築
  def build_inventory_scope(authenticated: false)
    if authenticated && @store
      # 認証済み: 店舗スコープでの詳細情報
      @store.store_inventories
            .joins(:inventory)
            .includes(:inventory)
    else
      # 公開アクセス: 基本情報のみ
      StoreInventory.joins(:inventory, :store)
                    .includes(:inventory, :store)
                    .where(stores: { active: true })
    end
  end

  # 検索・フィルタリング機能
  def apply_filters(scope, search_params = {})
    return scope if search_params.blank?

    filtered_scope = scope

    # 商品名検索
    if search_params[:name_cont].present?
      name_query = sanitize_search_term(search_params[:name_cont])
      filtered_scope = filtered_scope.where(
        Arel.sql("inventories.name ILIKE ?"),
        "%#{name_query}%"
      )
    end

    # カテゴリ検索（商品名パターンマッチング）
    if search_params[:category_eq].present?
      category = search_params[:category_eq]
      category_pattern = category_keywords_map[category]
      if category_pattern
        filtered_scope = filtered_scope.where(
          Arel.sql("inventories.name ~* ?"),
          category_pattern
        )
      end
    end

    # 在庫レベルフィルタ
    if search_params[:stock_level_eq].present?
      filtered_scope = apply_stock_level_filter(
        filtered_scope,
        search_params[:stock_level_eq]
      )
    end

    filtered_scope
  end

  # 統計情報の計算
  def calculate_statistics(scope)
    store_inventories = scope.to_a

    {
      total_items: store_inventories.count,
      total_value: calculate_total_value(store_inventories),
      low_stock_percentage: calculate_low_stock_percentage(store_inventories),
      out_of_stock_count: store_inventories.count { |si| si.quantity <= 0 },
      low_stock_count: store_inventories.count { |si| si.quantity > 0 && si.reorder_level.present? && si.quantity <= si.reorder_level }
    }
  end

  # 在庫調整処理
  def adjust_inventory(inventory, adjustment_params)
    store_inventory = @store.store_inventories.find_by!(inventory: inventory)

    ActiveRecord::Base.transaction do
      old_quantity = store_inventory.quantity
      new_quantity = adjustment_params[:new_quantity].to_i
      adjustment_reason = adjustment_params[:reason] || "在庫調整"

      # 在庫数量の更新
      store_inventory.update!(quantity: new_quantity)

      # InventoryLogの作成
      create_inventory_log(
        inventory: inventory,
        store_inventory: store_inventory,
        old_quantity: old_quantity,
        new_quantity: new_quantity,
        reason: adjustment_reason
      )

      { success: true, store_inventory: store_inventory }
    end
  rescue ActiveRecord::RecordInvalid => e
    { success: false, errors: e.record.errors }
  rescue StandardError => e
    { success: false, errors: { base: [ e.message ] } }
  end

  private

  # セキュリティ: 検索語のサニタイズ
  def sanitize_search_term(term)
    # SQLインジェクション防止
    term.to_s.gsub(/[%_\\]/) { |char| "\\#{char}" }.strip
  end

  # カテゴリキーワードマッピング
  def category_keywords_map
    {
      "医薬品" => "(薬|錠|カプセル|シロップ|軟膏|目薬|点鼻|吸入|注射|輸液)",
      "医療機器" => "(器具|機器|装置|測定|検査|手術|治療|診断)",
      "消耗品" => "(ガーゼ|包帯|綿|手袋|マスク|注射器|針|カテーテル|チューブ)",
      "衛生用品" => "(消毒|洗浄|清拭|石鹸|アルコール|ワイプ|タオル)"
    }
  end

  # 在庫レベルフィルタの適用
  def apply_stock_level_filter(scope, level)
    case level
    when "out_of_stock"
      scope.where(Arel.sql("store_inventories.quantity <= 0"))
    when "low_stock"
      scope.where(
        Arel.sql("store_inventories.quantity > 0 AND store_inventories.quantity <= store_inventories.reorder_level")
      )
    when "adequate_stock"
      scope.where(
        Arel.sql("store_inventories.quantity > store_inventories.reorder_level")
      )
    else
      scope
    end
  end

  # 合計価値の計算
  def calculate_total_value(store_inventories)
    store_inventories.sum do |store_inventory|
      inventory = store_inventory.inventory
      unit_cost = inventory.respond_to?(:unit_cost) ? inventory.unit_cost.to_f : 0
      store_inventory.quantity.to_f * unit_cost
    end
  end

  # 低在庫率の計算
  def calculate_low_stock_percentage(store_inventories)
    return 0 if store_inventories.empty?

    low_stock_count = store_inventories.count do |si|
      si.quantity > 0 && si.reorder_level.present? && si.quantity <= si.reorder_level
    end

    (low_stock_count.to_f / store_inventories.count * 100).round(1)
  end

  # InventoryLogの作成
  def create_inventory_log(inventory:, store_inventory:, old_quantity:, new_quantity:, reason:)
    InventoryLog.create!(
      inventory: inventory,
      store: @store,
      user: @current_user,
      admin: nil, # 店舗ユーザーによる操作
      action: "manual_adjustment",
      quantity_before: old_quantity,
      quantity_after: new_quantity,
      quantity_changed: new_quantity - old_quantity,
      reason: reason,
      metadata: {
        store_inventory_id: store_inventory.id,
        adjusted_by: @current_user&.email,
        timestamp: Time.current.iso8601
      }
    )
  end
end
