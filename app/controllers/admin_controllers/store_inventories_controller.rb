# frozen_string_literal: true

module AdminControllers
  # 管理者用店舗別在庫管理コントローラー
  # ============================================
  # Phase 3: マルチストア対応
  # 管理者は全店舗の詳細な在庫情報にアクセス可能
  # CLAUDE.md準拠: 権限に基づいた適切な情報開示
  # ============================================
  class StoreInventoriesController < BaseController
    before_action :set_store
    before_action :authorize_store_access
    before_action :set_inventory, only: [ :details ]

    # ============================================
    # アクション
    # ============================================

    # 店舗別在庫一覧（管理者用詳細版）
    def index
      # N+1クエリ対策（CLAUDE.md: パフォーマンス最適化）
      # CLAUDE.md準拠: ransack代替実装でセキュリティとパフォーマンスを両立
      # 🔧 パフォーマンス最適化: 管理者一覧画面でもbatches情報は不要
      # メタ認知: 一覧表示では在庫数量・価格等の基本情報のみ必要
      # 横展開: 店舗画面のindex最適化と同様のパターン適用
      base_scope = @store.store_inventories
                         .joins(:inventory)
                         .includes(:inventory)

      # 検索条件の適用（ransackの代替）
      @q = apply_search_filters(base_scope, params[:q] || {})

      @store_inventories = @q.order(sort_column => sort_direction)
                            .page(params[:page])
                            .per(params[:per_page] || 25)

      # 統計情報（管理者用詳細版）
      @statistics = calculate_detailed_statistics

      respond_to do |format|
        format.html
        format.json { render json: detailed_inventory_json }
        format.csv { send_data generate_csv, filename: csv_filename }
        format.xlsx { send_data generate_xlsx, filename: xlsx_filename }
      end
    end

    # 在庫詳細情報（価格・仕入先含む）
    def details
      @store_inventory = @store.store_inventories.find_by!(inventory: @inventory)
      # CLAUDE.md準拠: inventory_logsはグローバルレコード（店舗別ではない）
      # メタ認知: inventory_logsテーブルにstore_idカラムは存在しない
      # 横展開: StoreControllers::Inventoriesでも同様の修正実施済み
      # TODO: 🟡 Phase 2（重要）- 店舗別在庫変動履歴の実装検討
      #   - store_inventory_logsテーブルの新規作成
      #   - StoreInventoryモデルでの変動追跡
      #   - 現在は全体の在庫ログを表示（店舗フィルタなし）
      @inventory_logs = @inventory.inventory_logs
                                 .includes(:admin)
                                 .order(created_at: :desc)
                                 .limit(50)

      @transfer_history = load_transfer_history
      @batch_details = @inventory.batches.includes(:receipts)

      respond_to do |format|
        format.html
        format.json { render json: inventory_details_json }
      end
    end

    private

    # ============================================
    # 認可
    # ============================================

    def set_store
      @store = Store.find(params[:store_id])
    end

    def authorize_store_access
      # TODO: Phase 5 - CanCanCan統合後、より詳細な権限制御
      #   - 本社管理者: 全店舗アクセス可
      #   - 地域管理者: 担当地域の店舗のみ
      #   - 店舗管理者: 自店舗のみ
      unless current_admin.can_access_store?(@store)
        redirect_to admin_stores_path,
                   alert: "この店舗の在庫情報にアクセスする権限がありません"
      end
    end

    def set_inventory
      @inventory = Inventory.find(params[:id])
    end

    # ============================================
    # データ処理
    # ============================================

    def calculate_detailed_statistics
      # TODO: 🔴 Phase 4（緊急）- categoryカラム追加の検訍
      # 優先度: 高（機能完成度向上）
      # 実装内容: マイグレーションでcategoryカラム追加後、正確なカテゴリ分析が可能

      # 暫定実装: パターンベースカテゴリ数カウント
      # CLAUDE.md準拠: スキーマ不一致問題の解決
      inventories = @store.inventories.select(:id, :name)
      category_count = inventories.map { |inv| categorize_by_name(inv.name) }
                                  .uniq
                                  .compact
                                  .count

      {
        total_items: @store.store_inventories.count,
        total_quantity: @store.store_inventories.sum(:quantity),
        total_value: @store.total_inventory_value,
        low_stock_items: @store.low_stock_items_count,
        out_of_stock_items: @store.out_of_stock_items_count,
        categories: category_count,
        last_updated: @store.store_inventories.maximum(:updated_at),
        inventory_turnover: @store.inventory_turnover_rate,
        average_stock_value: @store.total_inventory_value / @store.store_inventories.count.to_f
      }
    end

    def detailed_inventory_json
      {
        store: store_summary,
        statistics: @statistics,
        inventories: @store_inventories.map { |si| inventory_item_json(si) },
        pagination: pagination_info
      }
    end

    def inventory_details_json
      {
        inventory: @inventory.as_json,
        store_inventory: @store_inventory.as_json,
        statistics: {
          current_quantity: @store_inventory.quantity,
          reserved_quantity: @store_inventory.reserved_quantity,
          available_quantity: @store_inventory.available_quantity,
          safety_stock_level: @store_inventory.safety_stock_level,
          total_value: @store_inventory.quantity * @inventory.price
        },
        batches: @batch_details.map(&:as_json),
        recent_logs: @inventory_logs.first(10).map(&:as_json),
        transfer_history: @transfer_history.map(&:as_json)
      }
    end

    def store_summary
      {
        id: @store.id,
        name: @store.name,
        code: @store.code,
        type: @store.store_type,
        address: @store.address,
        active: @store.active
      }
    end

    def inventory_item_json(store_inventory)
      {
        id: store_inventory.id,
        inventory: {
          id: store_inventory.inventory.id,
          name: store_inventory.inventory.name,
          sku: store_inventory.inventory.sku,
          category: categorize_by_name(store_inventory.inventory.name),
          # ✅ Phase 1（完了）- manufacturerカラム復活
          manufacturer: store_inventory.inventory.manufacturer,
          unit: store_inventory.inventory.unit,
          price: store_inventory.inventory.price,
          status: store_inventory.inventory.status
        },
        quantity: store_inventory.quantity,
        reserved_quantity: store_inventory.reserved_quantity,
        available_quantity: store_inventory.available_quantity,
        safety_stock_level: store_inventory.safety_stock_level,
        stock_status: stock_status(store_inventory),
        total_value: store_inventory.quantity * store_inventory.inventory.price,
        last_updated: store_inventory.updated_at
      }
    end

    def pagination_info
      {
        current_page: @store_inventories.current_page,
        total_pages: @store_inventories.total_pages,
        total_count: @store_inventories.total_count,
        per_page: @store_inventories.limit_value
      }
    end

    # ============================================
    # エクスポート機能
    # ============================================

    def generate_csv
      CSV.generate(headers: true) do |csv|
        csv << csv_headers

        @store_inventories.find_each do |store_inventory|
          csv << csv_row(store_inventory)
        end
      end
    end

    def csv_headers
      [
        "商品ID", "SKU", "商品名", "カテゴリ", "メーカー", "単位",
        "在庫数", "予約数", "利用可能数", "安全在庫", "単価",
        "在庫金額", "在庫状態", "最終更新"
      ]
    end

    def csv_row(store_inventory)
      inv = store_inventory.inventory
      [
        inv.id,
        inv.sku,
        inv.name,
        categorize_by_name(inv.name),
        # ✅ Phase 1（完了）- manufacturerカラム復活
        inv.manufacturer,
        inv.unit,
        store_inventory.quantity,
        store_inventory.reserved_quantity,
        store_inventory.available_quantity,
        store_inventory.safety_stock_level,
        inv.price,
        store_inventory.quantity * inv.price,
        stock_status_text(store_inventory),
        store_inventory.updated_at.strftime("%Y-%m-%d %H:%M")
      ]
    end

    def csv_filename
      "#{@store.code}_inventories_#{Date.current.strftime('%Y%m%d')}.csv"
    end

    def xlsx_filename
      "#{@store.code}_inventories_#{Date.current.strftime('%Y%m%d')}.xlsx"
    end

    # TODO: Phase 5 - Excel生成機能
    def generate_xlsx
      # Axlsx gem等を使用したExcel生成
      "Excel export not implemented yet"
    end

    # ============================================
    # ヘルパーメソッド
    # ============================================

    def load_transfer_history
      InterStoreTransfer.where(
        "(source_store_id = :store_id OR destination_store_id = :store_id) AND inventory_id = :inventory_id",
        store_id: @store.id,
        inventory_id: @inventory.id
      ).includes(:source_store, :destination_store, :requested_by, :approved_by)
       .order(created_at: :desc)
       .limit(20)
    end

    def stock_status(store_inventory)
      if store_inventory.quantity == 0
        :out_of_stock
      elsif store_inventory.quantity <= store_inventory.safety_stock_level
        :low_stock
      elsif store_inventory.quantity > store_inventory.safety_stock_level * 3
        :excess_stock
      else
        :normal_stock
      end
    end

    def stock_status_text(store_inventory)
      I18n.t("inventory.stock_status.#{stock_status(store_inventory)}")
    end

    # 検索フィルターの適用（ransack代替実装）
    # CLAUDE.md準拠: SQLインジェクション対策とパフォーマンス最適化
    # TODO: 🔴 Phase 2（緊急）- 管理者向け高度検索機能
    #   - 店舗間在庫比較検索
    #   - 価格・仕入先情報でのフィルタリング
    #   - バッチ期限による絞り込み
    #   - 横展開: 検索ロジックの共通ライブラリ化検討
    def apply_search_filters(scope, search_params)
      # 基本的な名前検索
      if search_params[:name_cont].present?
        scope = scope.where("inventories.name LIKE ?", "%#{sanitize_sql_like(search_params[:name_cont])}%")
      end

      # カテゴリフィルター（商品名パターンマッチング）
      if search_params[:category_eq].present?
        category_keywords = category_keywords_map[search_params[:category_eq]]
        if category_keywords
          scope = scope.where("inventories.name REGEXP ?", category_keywords.join("|"))
        end
      end

      # 在庫レベルフィルター
      if search_params[:stock_level_eq].present?
        case search_params[:stock_level_eq]
        when "out_of_stock"
          # 🔧 SQL修正: テーブル名明示でカラム曖昧性解消（横展開修正）
          # CLAUDE.md準拠: 他コントローラーと一貫した修正パターン適用
          scope = scope.where("store_inventories.quantity = 0")
        when "low_stock"
          scope = scope.where("store_inventories.quantity > 0 AND store_inventories.quantity <= store_inventories.safety_stock_level")
        when "normal_stock"
          scope = scope.where("store_inventories.quantity > store_inventories.safety_stock_level AND store_inventories.quantity <= store_inventories.safety_stock_level * 2")
        when "excess_stock"
          scope = scope.where("store_inventories.quantity > store_inventories.safety_stock_level * 2")
        end
      end

      # メーカーフィルター（✅ 復活）
      if search_params[:manufacturer_eq].present?
        scope = scope.where("inventories.manufacturer = ?", search_params[:manufacturer_eq])
      end

      scope
    end

    # カテゴリキーワードマップ
    def category_keywords_map
      {
        "医薬品" => %w[錠 カプセル 軟膏 点眼 坐剤 注射 シロップ 細粒 顆粒 液 mg IU],
        "医療機器" => %w[血圧計 体温計 パルスオキシメーター 聴診器 測定器],
        "消耗品" => %w[マスク 手袋 アルコール ガーゼ 注射針],
        "サプリメント" => %w[ビタミン サプリ オメガ プロバイオティクス フィッシュオイル]
      }
    end

    # 商品名からカテゴリを推定するヘルパーメソッド
    # CLAUDE.md準拠: ベストプラクティス - 推定ロジックの明示化
    # 横展開: dashboard_controller.rb、inventories_controller.rbと同一ロジック
    def categorize_by_name(product_name)
      # 医薬品キーワード
      medicine_keywords = %w[錠 カプセル 軟膏 点眼 坐剤 注射 シロップ 細粒 顆粒 液 mg IU
                           アスピリン パラセタモール オメプラゾール アムロジピン インスリン
                           抗生 消毒 ビタミン プレドニゾロン エキス]

      # 医療機器キーワード
      device_keywords = %w[血圧計 体温計 パルスオキシメーター 聴診器 測定器]

      # 消耗品キーワード
      supply_keywords = %w[マスク 手袋 アルコール ガーゼ 注射針]

      # サプリメントキーワード
      supplement_keywords = %w[ビタミン サプリ オメガ プロバイオティクス フィッシュオイル]

      case product_name
      when /#{device_keywords.join('|')}/i
        "医療機器"
      when /#{supply_keywords.join('|')}/i
        "消耗品"
      when /#{supplement_keywords.join('|')}/i
        "サプリメント"
      when /#{medicine_keywords.join('|')}/i
        "医薬品"
      else
        "その他"
      end
    end

    # ============================================
    # ソート設定
    # ============================================

    def sort_column
      # TODO: 🔴 Phase 4（緊急）- categoryカラム追加後、inventories.categoryソート機能復旧
      # 現在はスキーマに存在しないため除外
      allowed_columns = %w[
        inventories.name inventories.sku
        store_inventories.quantity store_inventories.updated_at
      ]
      allowed_columns.include?(params[:sort]) ? params[:sort] : "inventories.name"
    end

    def sort_direction
      %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
    end
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 高度な検索・フィルタリング
#    - 在庫状態フィルター
#    - 期限切れ間近のバッチ検索
#    - 移動履歴検索
#
# 2. 🟡 バッチ操作機能
#    - 複数商品の一括更新
#    - 一括移動申請
#    - 一括CSV更新
#
# 3. 🟢 分析・レポート機能
#    - 在庫回転率分析
#    - ABC分析
#    - 需要予測連携
