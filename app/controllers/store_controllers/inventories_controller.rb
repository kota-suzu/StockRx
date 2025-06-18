# frozen_string_literal: true

module StoreControllers
  # 店舗在庫管理コントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # 店舗スコープでの在庫閲覧・管理
  # ============================================
  class InventoriesController < BaseController
    # CLAUDE.md準拠: 店舗用ページネーション設定
    # メタ認知: 店舗スタッフ向けなので見やすい標準サイズを固定
    # 横展開: AuditLogsController, InventoryLogsControllerと同一パターンで一貫性確保
    PER_PAGE = 20

    before_action :set_inventory, only: [ :show, :request_transfer ]

    # ============================================
    # アクション
    # ============================================

    # 在庫一覧
    def index
      # 🔧 CLAUDE.md準拠: 認証状態に応じたアクセス制御
      # メタ認知: 公開アクセスと認証アクセスの適切な分離
      # セキュリティ: 機密情報は認証後のみ表示

      if store_user_signed_in? && current_store
        # 認証済み: 店舗スコープでの詳細情報
        # 🔧 パフォーマンス最適化: index画面ではbatches情報不要
        # CLAUDE.md準拠: 必要最小限の関連データのみ読み込み
        # メタ認知: 一覧表示ではバッチ詳細まで表示しないため除去
        base_scope = current_store.store_inventories
                                 .joins(:inventory)
                                 .includes(:inventory)
        @authenticated_access = true
      else
        # 公開アクセス: 基本情報のみ（価格等の機密情報除く）
        # TODO: 🟡 Phase 2（重要）- 公開用の店舗選択機能実装
        # 優先度: 中（ユーザビリティ向上）
        # 実装内容: URLパラメータまたはセッションによる店舗指定
        # 暫定: 全店舗の在庫を表示（実際の運用では店舗指定が必要）
        # 🔧 パフォーマンス最適化: 公開アクセスでもbatches情報不要
        base_scope = StoreInventory.joins(:inventory, :store)
                                  .includes(:inventory, :store)
                                  .where(stores: { active: true })
        @authenticated_access = false
      end

      # 検索条件の適用（ransackの代替）
      @q = apply_search_filters(base_scope, params[:q] || {})

      @store_inventories = @q.order(sort_column => sort_direction)
                            .page(params[:page])
                            .per(PER_PAGE)

      # フィルタリング用のデータ
      load_filter_data

      # 統計情報（認証済みの場合のみ詳細表示）
      load_statistics if @authenticated_access

      # CLAUDE.md準拠: CSV出力機能の実装
      # メタ認知: データエクスポート機能により業務効率向上
      # セキュリティ: 認証済みユーザーのみアクセス可能、店舗スコープ確保
      # 横展開: 他の一覧画面でも同様のCSV出力パターン適用可能
      respond_to do |format|
        format.html # 通常のHTML表示
        format.csv do
          # CSVダウンロード専用処理
          generate_csv_response
        end
      end
    end

    # 在庫詳細
    def show
      # 🔧 パフォーマンス最適化: 不要なeager loading削除
      # CLAUDE.md準拠: Bullet警告解消 - includes(inventory: :batches)の重複解消
      # メタ認知: ビューで@batchesを別途取得するため、事前読み込み不要
      # 理由: inventory情報のみアクセスするため、inventoryのみinclude
      # TODO: 🟡 Phase 3（重要）- パフォーマンス監視体制の確立
      # 優先度: 中（継続的改善）
      # 実装内容:
      #   - Bullet gem警告の自動検出・通知システム
      #   - SQL実行時間のモニタリング（NewRelic/DataDog）
      #   - N+1クエリパターンの文書化と予防策
      #   - レスポンス時間SLO設定（95percentile < 200ms）
      # 期待効果: 継続的なパフォーマンス改善とユーザー体験向上
      @store_inventory = current_store.store_inventories
                                     .includes(:inventory)
                                     .find_by!(inventory: @inventory)

      # バッチ情報（正しいアソシエーション経由でアクセス）
      # TODO: 🟡 Phase 3（重要）- バッチ表示の高速化
      # 優先度: 中（ユーザー体験向上）
      # 現状: ページネーション済みだが、N+1の可能性
      # 改善案: inventory.batches経由よりもBatch.where(inventory: @inventory)
      # 期待効果: さらなるクエリ最適化とレスポンス向上
      @batches = @inventory.batches
                          .order(expires_on: :asc)
                          .page(params[:batch_page])

      # 在庫履歴
      # CLAUDE.md準拠: inventory_logsはグローバルレコードで店舗別ではない
      # メタ認知: inventory_logsテーブルにstore_idカラムは存在しない
      # 横展開: 他のコントローラーでも同様の誤解がないか確認必要
      # TODO: 🟡 Phase 2（重要）- 店舗別在庫変動履歴の実装検討
      #   - store_inventory_logsテーブルの新規作成
      #   - StoreInventoryモデルでの変動追跡
      #   - 現在は全体の在庫ログを表示（店舗フィルタなし）
      @inventory_logs = @inventory.inventory_logs
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

      # 🔧 CLAUDE.md準拠: 認証状態に応じたデータソース選択
      # メタ認知: 公開アクセス時はcurrent_storeがnilのため条件分岐必要
      # セキュリティ: 公開時は基本情報のみ、認証時は詳細情報
      if @authenticated_access && current_store
        # 認証済み: 店舗スコープでの詳細情報
        inventories = current_store.inventories.select(:id, :name)
        manufacturer_scope = current_store.inventories
      else
        # 公開アクセス: 全店舗のアクティブ在庫から基本情報のみ
        inventories = Inventory.joins(:store_inventories)
                              .joins("JOIN stores ON store_inventories.store_id = stores.id")
                              .where("stores.active = 1")
                              .select(:id, :name)
                              .distinct
        manufacturer_scope = Inventory.joins(:store_inventories)
                                    .joins("JOIN stores ON store_inventories.store_id = stores.id")
                                    .where("stores.active = 1")
      end

      # 暫定実装: 商品名パターンによるカテゴリ推定
      # CLAUDE.md準拠: スキーマ不一致問題の解決（category不存在）
      # 横展開: dashboard_controller.rbと同様のパターンマッチング手法活用
      @categories = inventories.map { |inv| categorize_by_name(inv.name) }
                               .uniq
                               .compact
                               .sort

      # ✅ Phase 1（完了）- manufacturerカラム追加完了
      # マイグレーション実行済み: AddMissingColumnsToInventories
      # カラム追加: sku, manufacturer, unit
      @manufacturers = manufacturer_scope
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
    # CLAUDE.md準拠: 代替検索パターンでのActiveRecord::Relation使用
    # メタ認知: ransack依存を除去し、@qを直接使用
    # 横展開: 他コントローラーでも同様のパターン適用
    def calculate_low_stock_percentage
      total = @q.count
      return 0 if total.zero?

      low_stock = @q.where("store_inventories.quantity <= store_inventories.safety_stock_level").count
      ((low_stock.to_f / total) * 100).round(1)
    end

    # 移動履歴の読み込み
    def load_transfer_history
      # 🔧 パフォーマンス最適化: 未使用のeager loading削除
      # CLAUDE.md準拠: ビューで表示しない関連は読み込まない
      # メタ認知: 移動履歴は現在ビューで表示されていない
      # TODO: 🟡 Phase 3（重要）- 移動履歴表示機能の実装
      #   - ビューに移動履歴セクション追加時に必要な関連を再検討
      InterStoreTransfer.where(
        "(source_store_id = :store_id OR destination_store_id = :store_id) AND inventory_id = :inventory_id",
        store_id: current_store.id,
        inventory_id: @inventory.id
      ).includes(:source_store, :destination_store)
       .order(created_at: :desc)
       .limit(10)
    end

    # ============================================
    # ソート設定
    # ============================================

    # CLAUDE.md準拠: ソート機能のヘルパーメソッド化
    # メタ認知: ビューでソートリンクを生成するために必要
    # ベストプラクティス: 明示的なhelper_method宣言で可読性向上
    # 横展開: 他のコントローラーでも同様のパターン確認必要
    # TODO: 🟡 Phase 3（重要）- ソート機能の統一化
    # 優先度: 中（コード一貫性向上）
    # 現状: store_inventories_controller, admin_controllers/store_inventories_controller
    #      にも同様のソートメソッドがあるが、helper_method宣言なし
    # 対応: 各ビューでソート機能が必要になった際に同様の修正適用
    # 期待効果: 一貫性のあるソート機能の実装、保守性向上
    helper_method :sort_column, :sort_direction

    def sort_column
      # 🔧 CLAUDE.md準拠: 認証状態に応じたカラム名の調整
      # メタ認知: 公開アクセス時はJOINが発生するため、曖昧性を回避
      # セキュリティ: SQLインジェクション対策として許可リストを使用
      allowed_columns = %w[inventories.name inventories.sku store_inventories.quantity store_inventories.safety_stock_level]

      if allowed_columns.include?(params[:sort])
        params[:sort]
      else
        "inventories.name"  # デフォルトカラム
      end
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
          scope = scope.where("inventories.name REGEXP ?", category_keywords.join("|"))
        end
      end

      # 在庫レベルフィルター
      if search_params[:stock_level_eq].present?
        case search_params[:stock_level_eq]
        when "out_of_stock"
          # 🔧 SQL修正: テーブル名明示でカラム曖昧性解消（横展開修正）
          # CLAUDE.md準拠: store_inventoriesテーブルのquantity指定
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

    # ============================================
    # CSV出力処理
    # ============================================

    # CSV生成とレスポンス処理
    # CLAUDE.md準拠: セキュリティとユーザビリティのベストプラクティス
    # メタ認知: CSV出力により店舗業務の効率化とデータ活用促進
    # 横展開: 他の一覧画面でも同様のCSVパターン適用可能
    def generate_csv_response
      # 認証チェック（念のため）
      unless store_user_signed_in? && current_store
        redirect_to stores_path, alert: "アクセス権限がありません"
        return
      end

      # CSV生成用データ取得（ページネーションなしで全件）
      csv_data = fetch_csv_data

      # CSVファイル名生成（日本語対応）
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "#{current_store.name}_在庫一覧_#{timestamp}.csv"

      # CSVレスポンス設定
      # CLAUDE.md準拠: 文字エンコーディングとダウンロード設定のベストプラクティス
      response.headers['Content-Type'] = 'text/csv; charset=utf-8'
      response.headers['Content-Disposition'] = "attachment; filename*=UTF-8''#{ERB::Util.url_encode(filename)}"

      # BOM付きUTF-8で出力（Excel対応）
      csv_content = "\uFEFF" + generate_csv_content(csv_data)

      # 監査ログ記録
      log_csv_export_event(csv_data.count)

      # CSVレスポンス送信
      render plain: csv_content
    end

    # CSV用データ取得
    # CLAUDE.md準拠: パフォーマンス最適化とセキュリティ確保
    def fetch_csv_data
      # 店舗スコープでの全データ取得（セキュリティ確保）
      base_scope = current_store.store_inventories
                                .joins(:inventory)
                                .includes(:inventory)

      # 検索条件適用（index と同じロジック）
      @q = apply_search_filters(base_scope, params[:q] || {})

      # ソート適用（ページネーションなし）
      @q.order(sort_column => sort_direction)
    end

    # CSV内容生成
    # CLAUDE.md準拠: 読みやすいCSVヘッダーと適切なデータフォーマット
    def generate_csv_content(store_inventories)
      require 'csv'

      CSV.generate(headers: true) do |csv|
        # CSVヘッダー
        csv << [
          "商品名",
          "商品コード", 
          "カテゴリ",
          "現在在庫数",
          "安全在庫レベル",
          "単価",
          "在庫価値",
          "在庫状態",
          "回転日数",
          "最終更新日"
        ]

        # データ行
        store_inventories.find_each do |store_inventory|
          csv << [
            store_inventory.inventory.name,
            store_inventory.inventory.sku || "---",
            categorize_by_name(store_inventory.inventory.name),
            store_inventory.quantity,
            store_inventory.safety_stock_level,
            store_inventory.inventory.price,
            (store_inventory.quantity * store_inventory.inventory.price),
            extract_stock_status_text(store_inventory),
            turnover_days(store_inventory),
            store_inventory.last_updated_at&.strftime("%Y/%m/%d %H:%M") || "---"
          ]
        end
      end
    end

    # 在庫状態テキスト抽出
    def extract_stock_status_text(store_inventory)
      badge_info = stock_level_badge(store_inventory)
      badge_info[:text]
    end

    # CSV出力監査ログ記録
    # CLAUDE.md準拠: セキュリティコンプライアンスとトレーサビリティ確保
    def log_csv_export_event(record_count)
      # 基本情報
      event_details = {
        action: "inventory_csv_export",
        store_id: current_store.id,
        store_name: current_store.name,
        user_id: current_store_user.id,
        record_count: record_count,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        timestamp: Time.current.iso8601
      }

      # ログ記録
      Rails.logger.info "[CSV_EXPORT] Store inventory export: #{event_details.to_json}"

      # TODO: 🟡 Phase 3（重要）- セキュリティ監査ログとの統合
      # 優先度: 中（コンプライアンス強化）
      # 実装内容: SecurityComplianceManagerとの統合
      # SecurityComplianceManager.instance.log_gdpr_event(
      #   "data_export", current_store_user, event_details
      # )
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
