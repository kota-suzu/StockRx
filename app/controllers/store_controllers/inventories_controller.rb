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
      # CLAUDE.md準拠: ransack代替実装でセキュリティとパフォーマンスを両立
      # メタ認知: AdvancedSearchQueryパターンと一貫性を保つ
      base_scope = current_store.store_inventories
                               .joins(:inventory)
                               .includes(inventory: :batches)

      # 検索条件の適用（ransackの代替）
      @q = apply_search_filters(base_scope, params[:q] || {})

      @store_inventories = @q.order(sort_column => sort_direction)
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
                                     .includes(inventory: :batches)
                                     .find_by!(inventory: @inventory)

      # バッチ情報（正しいアソシエーション経由でアクセス）
      @batches = @inventory.batches
                          .order(expires_on: :asc)
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
      # TODO: 🔴 Phase 4（緊急）- categoryカラム追加の検討
      # 優先度: 高（機能完成度向上）
      # 実装内容:
      #   - マイグレーション: add_column :inventories, :category, :string
      #   - seeds.rb更新: カテゴリ情報の実際の保存
      #   - バックフィル: 既存データへのカテゴリ自動割り当て
      # 期待効果: 正確なカテゴリ分析、将来的な商品管理機能拡張

      # 暫定実装: 商品名パターンによるカテゴリ推定
      # CLAUDE.md準拠: スキーマ不一致問題の解決（category不存在）
      # 横展開: dashboard_controller.rbと同様のパターンマッチング手法活用
      inventories = current_store.inventories.select(:id, :name)
      @categories = inventories.map { |inv| categorize_by_name(inv.name) }
                               .uniq
                               .compact
                               .sort

      # TODO: 🔴 Phase 1（緊急）- manufacturerカラム追加
      # 優先度: 最高（現在エラーの原因）
      # 問題: manufacturerカラムがinventoriesテーブルに存在しない
      # 実装内容:
      #   - マイグレーション: add_column :inventories, :manufacturer, :string
      #   - seeds.rb更新: メーカー情報の実際の保存
      #   - バックフィル: 既存データへのメーカー情報推定・割り当て
      # 横展開: AdminControllers::StoreInventoriesController等でも同様修正必要
      # 暫定対応: manufacturerフィルターを無効化
      @manufacturers = []  # 空配列で暫定対応

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
        total_items: @q.count,
        total_quantity: @q.sum(:quantity),
        total_value: calculate_total_value(@q),
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

    private

    # 検索フィルターの適用（ransack代替実装）
    # CLAUDE.md準拠: SQLインジェクション対策とパフォーマンス最適化
    # TODO: 🟡 Phase 3（重要）- 検索機能の拡張
    #   - 全文検索機能（MySQL FULLTEXT INDEX活用）
    #   - 検索結果のハイライト表示
    #   - 検索履歴・お気に入り機能
    #   - 横展開: AdminControllers::StoreInventoriesControllerと共通化
    def apply_search_filters(scope, search_params)
      # 基本的な名前検索
      if search_params[:name_cont].present?
        scope = scope.where("inventories.name LIKE ?", "%#{sanitize_sql_like(search_params[:name_cont])}%")
      end

      # カテゴリフィルター（商品名パターンマッチング）
      if search_params[:category_eq].present?
        category_keywords = category_keywords_map[search_params[:category_eq]]
        if category_keywords
          scope = scope.where("inventories.name REGEXP ?", category_keywords.join('|'))
        end
      end

      # 在庫レベルフィルター
      if search_params[:stock_level_eq].present?
        case search_params[:stock_level_eq]
        when 'out_of_stock'
          scope = scope.where(quantity: 0)
        when 'low_stock'
          scope = scope.where("store_inventories.quantity > 0 AND store_inventories.quantity <= store_inventories.safety_stock_level")
        when 'normal_stock'
          scope = scope.where("store_inventories.quantity > store_inventories.safety_stock_level AND store_inventories.quantity <= store_inventories.safety_stock_level * 2")
        when 'excess_stock'
          scope = scope.where("store_inventories.quantity > store_inventories.safety_stock_level * 2")
        end
      end

      # メーカーフィルター（暫定無効化）
      # TODO: 🔴 Phase 1（緊急）- manufacturerカラム追加後に有効化
      # if search_params[:manufacturer_eq].present?
      #   scope = scope.where("inventories.manufacturer = ?", search_params[:manufacturer_eq])
      # end

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
    # 横展開: dashboard_controller.rbと同一ロジック
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
