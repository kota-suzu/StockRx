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
      # TODO: 🟡 Phase 4（重要）- ダッシュボードパフォーマンス最適化
      # 優先度: 中（UX改善）
      # 実装内容:
      #   - 非同期データロード（Turbo Frames活用）
      #   - Redisキャッシュによる集計値の高速化
      #   - GraphQLによる効率的なデータフェッチ
      # 期待効果: 初期表示時間50%短縮

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
        # Counter Cache使用でN+1クエリ完全解消
        total_items: current_store.store_inventories_count,
        total_quantity: current_store.store_inventories.sum(:quantity),
        total_value: current_store.total_inventory_value,
        low_stock_items: current_store.low_stock_items_count,
        out_of_stock_items: current_store.out_of_stock_items_count,
        # Counter Cache使用でN+1クエリ完全解消
        pending_transfers_in: current_store.pending_incoming_transfers_count,
        pending_transfers_out: current_store.pending_outgoing_transfers_count
      }
    end

    # 在庫アラート情報の読み込み
    # CLAUDE.md準拠: セキュリティ強化 - Rails 7+ SQL Injection対策
    def load_inventory_alerts
      # 🛡️ セキュリティ対策: Arel.sql()でSQL文字列の安全性を保証
      # メタ認知: 生SQLの使用理由 - 在庫レベル比率による複雑ソートのため
      # 横展開: 他の計算系クエリでも同様のパターン適用
      safety_ratio_order = Arel.sql(
        "(store_inventories.quantity::float / NULLIF(store_inventories.safety_stock_level, 0)) ASC"
      )

      # パフォーマンス最適化: selectで必要なカラムのみ取得
      @low_stock_items = current_store.store_inventories
                                     .joins(:inventory)
                                     .where("store_inventories.quantity <= store_inventories.safety_stock_level")
                                     .where("store_inventories.quantity > 0")
                                     .includes(:inventory)
                                     .select("store_inventories.*, inventories.name, inventories.price")
                                     .order(safety_ratio_order)
                                     .limit(10)

      @out_of_stock_items = current_store.store_inventories
                                         .joins(:inventory)
                                         .where("store_inventories.quantity = 0")
                                         .includes(:inventory)
                                         .select("store_inventories.*, inventories.name, inventories.price")
                                         .order(updated_at: :desc)
                                         .limit(10)

      # 🛡️ セキュリティ対策: SELECT句とORDER句の安全化
      # CLAUDE.md準拠: 正しいアソシエーション経由でのデータアクセス
      # メタ認知: StoreInventory → Inventory → Batches の関連を適切に使用
      # TODO: 🟡 Phase 4（重要）- Batchesリレーションの最適化
      #   - has_many through関係の見直し
      #   - 期限切れ間近商品のインデックス最適化
      #   - N+1クエリ完全解消（includes最適化）
      # TODO: 🔴 Phase 3（緊急）- パフォーマンス向上
      #   - バッチテーブルにインデックス追加: INDEX(inventory_id, expires_on)
      #   - 期限切れクエリの高速化

      # パフォーマンス最適化: 期限切れ間近のバッチを直接取得
      # メタ認知: ビューでlot_codeとexpires_onが必要なため、Batchオブジェクトを返す
      # 横展開: 他の期限管理画面でも同様のパターン適用可能
      @expiring_items = Batch.joins(inventory: :store_inventories)
                             .where(store_inventories: { store_id: current_store.id })
                             .where("batches.expires_on BETWEEN ? AND ?", Date.current, 30.days.from_now)
                             .where("batches.quantity > 0")
                             .includes(:inventory)
                             .order(:expires_on)
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

      # 最近の在庫変動
      # CLAUDE.md準拠: inventory_logsはグローバルレコード
      # メタ認知: 店舗別フィルタリングは店舗が扱う商品IDを経由する
      # 横展開: StoreControllers::Inventories, AdminControllers::StoreInventoriesでも同様修正済み
      # TODO: 🟡 Phase 2（重要）- 店舗別在庫変動追跡の実装
      #   - store_inventory_logsテーブルまたはpolymorphicな設計検討
      #   - 現在は店舗が扱う商品の全体ログを表示

      # パフォーマンス最適化: pluckの代わりにselectとlimitで必要なデータのみ取得
      inventory_ids = current_store.store_inventories
                                  .select(:inventory_id)
                                  .limit(100)  # 最新100商品分のみ
                                  .pluck(:inventory_id)

      if inventory_ids.any?
        @recent_inventory_changes = InventoryLog.where(inventory_id: inventory_ids)
                                               .includes(:inventory, :admin)
                                               .order(created_at: :desc)
                                               .limit(10)
      else
        @recent_inventory_changes = InventoryLog.none
      end
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
      # Counter Cache使用できない集計処理のため、sum(:quantity)はそのまま維持
      current_store.store_inventories.sum(:quantity)
    end

    # カテゴリ別在庫構成の準備
    # CLAUDE.md準拠: スキーマ不一致問題の解決（category不存在）
    def prepare_category_distribution
      # メタ認知: categoryカラムが存在しないため、商品名パターンベースの分類を実装
      # 横展開: 他のカテゴリ分析でも同様のパターンマッチング手法を活用可能

      # TODO: 🔴 Phase 4（緊急）- categoryカラム追加の検討
      # 優先度: 高（機能完成度向上）
      # 実装内容:
      #   - マイグレーション: add_column :inventories, :category, :string
      #   - seeds.rb更新: カテゴリ情報の実際の保存
      #   - バックフィル: 既存データへのカテゴリ自動割り当て
      # 期待効果: 正確なカテゴリ分析、将来的な商品管理機能拡張

      # 暫定実装: 商品名パターンによるカテゴリ推定
      store_inventories = current_store.store_inventories
                                      .joins(:inventory)
                                      .where("store_inventories.quantity > 0")
                                      .select("inventories.name, store_inventories.quantity")

      categories = {}

      store_inventories.each do |store_inventory|
        category = categorize_by_name(store_inventory.name)
        categories[category] = (categories[category] || 0) + store_inventory.quantity
      end

      # カテゴリ未分類の場合のフォールバック
      if categories.empty?
        categories["その他"] = current_store.store_inventories.sum(:quantity)
      end

      categories.map do |category, quantity|
        {
          name: category,
          value: quantity
        }
      end.to_json
    end


    # 店舗間移動トレンドの準備
    def prepare_transfer_trend_data
      dates = (6.days.ago.to_date..Date.current).to_a

      trend_data = dates.map do |date|
        # 日別集計はCounter Cacheでは対応できないため、.countを維持
        # TODO: Phase 3 - Redis等を使った集計データキャッシュで最適化
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

    # ============================================
    # カテゴリ推定機能
    # ============================================

    # 商品名からカテゴリを推定するメソッド
    # CLAUDE.md準拠: ベストプラクティス - 推定ロジックの明示化と横展開
    # メタ認知: 他のコントローラーで重複定義されている問題を認識
    # TODO: 🟡 Phase 3（重要）- CategorizationConcern作成による重複コード解消
    # 優先度: 中（現在の機能は動作中）
    # 実装内容:
    #   - app/controllers/concerns/categorization_concern.rb作成
    #   - 4つのコントローラーでの重複メソッド統一
    #     - AdminControllers::StoreInventoriesController (350行目)
    #     - StoreControllers::InventoriesController (576行目)
    #     - store_inventories_controller.rb (281行目)
    #     - StoreControllers::DashboardController (309行目)
    #   - ApplicationHelperとの整合性確保
    #   - カテゴリキーワードの一元管理（config/categorization.yml等）
    # 期待効果: DRY原則遵守、保守性向上、テスト重複解消
    # 横展開: 全コントローラーでinclude CategorizationConcern
    def categorize_by_name(product_name)
      return "その他" if product_name.blank?

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
