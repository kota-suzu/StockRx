# frozen_string_literal: true

module StoreControllers
  # 店舗在庫管理コントローラー（リファクタリング完了版）
  # ============================================
  # Phase 1: 責務分離完了 - サービスレイヤー活用
  # 店舗スコープでの在庫閲覧・管理
  # ============================================
  class InventoriesController < BaseController
    include ParameterSanitization

    # CLAUDE.md準拠: 店舗用ページネーション設定
    PER_PAGE = 20

    before_action :set_inventory, only: [ :show, :adjust_form, :adjust, :request_transfer_form, :request_transfer ]
    before_action :ensure_authenticated_store_user, only: [ :adjust_form, :adjust, :request_transfer_form, :request_transfer ]
    before_action :authorize_inventory_access, only: [ :show, :adjust_form, :adjust, :request_transfer_form, :request_transfer ]

    # ============================================
    # メインアクション
    # ============================================

    # 在庫一覧（リファクタリング済み）
    def index
      # Phase 1: サービスレイヤー活用による責務分離
      @authenticated_access = store_user_signed_in? && current_store

      # サービスインスタンスの初期化
      @management_service = StoreInventoryManagementService.new(
        store: current_store,
        current_user: current_store_user
      )

      # 基本スコープの構築
      base_scope = @management_service.build_inventory_scope(
        authenticated: @authenticated_access
      )

      # 検索・フィルタリングの適用
      filtered_scope = @management_service.apply_filters(
        base_scope,
        params[:q] || {}
      )

      # ソート・ページネーション
      @store_inventories = filtered_scope
                          .order(sort_column => sort_direction)
                          .page(params[:page])
                          .per(PER_PAGE)

      # フィルタリング用データの読み込み
      load_filter_data

      # 統計情報の計算（認証済みの場合のみ）
      if @authenticated_access
        @statistics = @management_service.calculate_statistics(filtered_scope)
      end

      # レスポンス形式の分岐
      respond_to do |format|
        format.html # 通常のHTML表示
        format.csv { generate_csv_response }
      end
    end

    # 在庫詳細（リファクタリング済み）
    def show
      # Phase 1: パフォーマンス最適化と責務明確化
      @store_inventory = current_store.store_inventories
                                     .includes(:inventory)
                                     .find_by!(inventory: @inventory)

      # バッチ情報の取得
      @batches = @inventory.batches
                          .order(expires_on: :asc)
                          .page(params[:batch_page])

      # 在庫履歴の取得
      @inventory_logs = @inventory.inventory_logs
                                 .includes(:admin)
                                 .order(created_at: :desc)
                                 .limit(20)

      # 移動履歴の取得（サービス経由）
      transfer_service = InventoryTransferService.new(current_user: current_store_user)
      @transfer_history = transfer_service.fetch_transfer_history(
        store: current_store,
        inventory: @inventory,
        limit: 10
      )
    end

    # 在庫調整フォーム表示
    def adjust_form
      @store_inventory = current_store.store_inventories.find_by!(inventory: @inventory)
    end

    # 在庫調整実行（リファクタリング済み）
    def adjust
      # Phase 1: サービスレイヤーによる処理委譲
      management_service = StoreInventoryManagementService.new(
        store: current_store,
        current_user: current_store_user
      )

      # パラメータの準備
      adjustment_params = params.dig(:adjustment) || {}

      result = management_service.adjust_inventory(
        @inventory,
        {
          new_quantity: adjustment_params[:new_quantity],
          reason: adjustment_params[:reason] || "在庫調整",
          notes: adjustment_params[:notes]
        }
      )

      if result[:success]
        old_qty = result[:store_inventory].quantity_was || 0
        new_qty = result[:store_inventory].quantity
        flash[:success] = "在庫調整が完了しました（#{old_qty} → #{new_qty}個）"
        redirect_to store_controllers_inventory_path(@inventory)
      else
        error_messages = result[:errors].respond_to?(:full_messages) ?
                        result[:errors].full_messages :
                        result[:errors].values.flatten
        flash[:alert] = "在庫調整に失敗しました: #{error_messages.join(', ')}"
        redirect_to adjust_form_store_controllers_inventory_path(@inventory)
      end
    end

    # 移動申請フォーム（リファクタリング済み）
    def request_transfer_form
      # Phase 1: サービス経由での処理
      @transfer_service = InventoryTransferService.new(current_user: current_store_user)

      # 移動可能な店舗リスト
      @available_stores = @transfer_service.available_target_stores(
        current_store: current_store
      )

      # 現在の在庫情報
      @current_store_inventory = current_store.store_inventories
                                            .find_by!(inventory: @inventory)

      # 移動履歴
      @transfer_history = @transfer_service.fetch_transfer_history(
        store: current_store,
        inventory: @inventory,
        limit: 10
      )
    end

    # 移動申請処理（リファクタリング済み）
    def request_transfer
      # Phase 1: サービス経由での処理委譲
      transfer_service = InventoryTransferService.new(current_user: current_store_user)

      result = transfer_service.create_transfer_request(
        from_store: current_store,
        inventory: @inventory,
        transfer_params: {
          to_store_id: params[:to_store_id],
          quantity: params[:quantity],
          reason: params[:reason] || "店舗間移動"
        }
      )

      if result[:success]
        flash[:notice] = result[:message]
        redirect_to store_controllers_inventory_path(@inventory)
      else
        flash[:alert] = "#{result[:message]}: #{result[:errors].join(', ')}"
        redirect_to request_transfer_form_store_controllers_inventory_path(@inventory)
      end
    end

    # ============================================
    # プライベートメソッド
    # ============================================

    private

    def set_inventory
      @inventory = Inventory.find(params[:id])
    end

    # フィルタリング用データの読み込み（簡略化）
    def load_filter_data
      @stores = Store.active.order(:name)
      @stock_level_options = [
        [ "在庫切れ", "out_of_stock" ],
        [ "低在庫", "low_stock" ],
        [ "適正在庫", "adequate_stock" ]
      ]
      @category_options = [
        [ "医薬品", "medical" ],
        [ "医療機器", "equipment" ],
        [ "消耗品", "consumables" ],
        [ "衛生用品", "hygiene" ]
      ]
    end

    # ソート設定
    def sort_column
      valid_columns = %w[name quantity safety_stock_level]
      params[:sort].in?(valid_columns) ? params[:sort] : "name"
    end

    def sort_direction
      %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
    end

    # CSV生成とレスポンス処理（リファクタリング済み）
    def generate_csv_response
      # 認証チェック
      unless store_user_signed_in? && current_store
        redirect_to stores_path, alert: "アクセス権限がありません"
        return
      end

      # Phase 1: CSVサービス経由での処理
      csv_service = CsvExportService.new(
        store: current_store,
        current_user: current_store_user
      )

      # データ取得（既存のロジック流用）
      csv_data = fetch_csv_data

      # CSV生成とファイル名作成
      csv_content = csv_service.generate_inventory_csv(csv_data)
      filename = csv_service.generate_filename("inventory_export")

      # Excel対応のBOM付きCSV
      csv_content_with_bom = "\uFEFF" + csv_content

      # レスポンスヘッダー設定
      response.headers["Content-Type"] = "text/csv; charset=utf-8"
      response.headers["Content-Disposition"] = "attachment; filename*=UTF-8''#{ERB::Util.url_encode(filename)}"

      render plain: csv_content_with_bom
    end

    # CSV用データ取得
    def fetch_csv_data
      base_scope = current_store.store_inventories
                               .joins(:inventory)
                               .includes(:inventory)

      # 検索条件適用（index と同じロジック）
      @q = apply_search_filters(base_scope, params[:q] || {})

      # ソート適用（ページネーションなし）
      @q.order(sort_column => sort_direction)
    end

    # 検索フィルタリングの適用（簡略化）
    # Phase 1: 基本機能のみ保持、詳細はStoreInventoryManagementServiceに移行
    def apply_search_filters(scope, search_params)
      return scope if search_params.blank?

      # 商品名検索
      if search_params[:name_cont].present?
        scope = scope.where(
          Arel.sql("inventories.name ILIKE ?"),
          "%#{search_params[:name_cont]}%"
        )
      end

      # 在庫レベルフィルタ
      if search_params[:stock_level_eq].present?
        case search_params[:stock_level_eq]
        when "out_of_stock"
          scope = scope.where(Arel.sql("store_inventories.quantity <= 0"))
        when "low_stock"
          scope = scope.where(
            Arel.sql("store_inventories.quantity > 0 AND store_inventories.quantity <= store_inventories.safety_stock_level")
          )
        when "adequate_stock"
          scope = scope.where(
            Arel.sql("store_inventories.quantity > store_inventories.safety_stock_level")
          )
        end
      end

      scope
    end

    # 認証・認可メソッド
    def ensure_authenticated_store_user
      unless store_user_signed_in? && current_store
        flash[:alert] = "この操作を行うにはログインが必要です"
        redirect_to store_selection_path and return
      end
    end

    def authorize_inventory_access
      return unless @inventory.present?
      verify_resource_store_scope
    end

    def verify_resource_store_scope
      return unless store_user_signed_in? && current_store

      if @inventory.present?
        store_inventory = current_store.store_inventories.find_by(inventory: @inventory)
        unless store_inventory
          flash[:alert] = "アクセス権限がありません"
          redirect_to store_controllers_inventories_path
        end
      end
    end
  end
end
