# frozen_string_literal: true

module StoreControllers
  # 店舗在庫管理コントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # 店舗スコープでの在庫閲覧・管理
  # ============================================
  class InventoriesController < BaseController
    include ParameterSanitization
    # CLAUDE.md準拠: 店舗用ページネーション設定
    # メタ認知: 店舗スタッフ向けなので見やすい標準サイズを固定
    # 横展開: AuditLogsController, InventoryLogsControllerと同一パターンで一貫性確保
    PER_PAGE = 20

    before_action :set_inventory, only: [ :show, :adjust_form, :adjust, :request_transfer_form, :request_transfer ]
    before_action :ensure_authenticated_store_user, only: [ :adjust_form, :adjust, :request_transfer_form, :request_transfer ]

    # QAレビュー対応: 店舗スコープ認可の強化
    before_action :authorize_inventory_access, only: [ :show, :adjust_form, :adjust, :request_transfer_form, :request_transfer ]

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

    # ============================================
    # 🔧 CLAUDE.md準拠: 在庫操作機能（Phase 3実装）
    # ============================================

    # 在庫調整フォーム表示
    # @inventory: 調整対象の在庫
    # @store_inventory: 店舗別在庫情報
    def adjust_form
      # メタ認知: 認証チェックはbefore_actionで実行済み
      # セキュリティ: 現在の店舗の在庫のみアクセス可能
      @store_inventory = current_store.store_inventories.find_by!(inventory: @inventory)

      # 調整履歴の取得（直近10件）
      @adjustment_history = @inventory.inventory_logs
                                    .where(operation_type: "adjustment")
                                    .includes(:admin)
                                    .order(created_at: :desc)
                                    .limit(10)
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

    # 移動申請フォーム表示
    # @inventory: 移動対象の在庫
    # @store_inventory: 現在店舗の在庫情報
    # @other_stores: 移動先候補店舗
    def request_transfer_form
      @store_inventory = current_store.store_inventories.find_by!(inventory: @inventory)

      # 移動先候補店舗（現在店舗以外のアクティブ店舗）
      @other_stores = Store.where.not(id: current_store.id)
                          .where(active: true)
                          .order(:name)

      # 移動履歴の取得（直近5件）
      @transfer_history = InterStoreTransfer.where(
        "(source_store_id = :store_id OR destination_store_id = :store_id) AND inventory_id = :inventory_id",
        store_id: current_store.id,
        inventory_id: @inventory.id
      ).includes(:source_store, :destination_store)
       .order(created_at: :desc)
       .limit(5)
    end

    # 移動申請作成
    # パラメータ: { transfer: { destination_store_id: 店舗ID, quantity: 数量, reason: 理由, notes: 備考 } }
    def request_transfer
      @store_inventory = current_store.store_inventories.find_by!(inventory: @inventory)

      # CLAUDE.md準拠: セキュアなパラメータ処理
      # パラメータのサニタイズと検証
      begin
        destination_store_id = sanitize_numeric(params.dig(:transfer, :destination_store_id),
                                              positive: true)
        quantity = sanitize_numeric(params.dig(:transfer, :quantity),
                                  positive: true, min: 1)
        reason = sanitize_string(params.dig(:transfer, :reason),
                               max_length: 255, normalize_whitespace: true)
        notes = sanitize_string(params.dig(:transfer, :notes),
                              max_length: 500, normalize_whitespace: true)
      rescue ArgumentError => e
        flash[:alert] = e.message
        redirect_to request_transfer_form_store_inventory_path(@inventory) and return
      end

      if destination_store_id.blank?
        flash[:alert] = "移動先店舗を選択してください"
        redirect_to request_transfer_form_store_inventory_path(@inventory) and return
      end

      if quantity.nil? || quantity <= 0
        flash[:alert] = "有効な移動数量を入力してください"
        redirect_to request_transfer_form_store_inventory_path(@inventory) and return
      end

      if quantity > @store_inventory.quantity
        flash[:alert] = "移動数量が現在在庫数を超えています"
        redirect_to request_transfer_form_store_inventory_path(@inventory) and return
      end

      if reason.blank?
        flash[:alert] = "移動理由を入力してください"
        redirect_to request_transfer_form_store_inventory_path(@inventory) and return
      end

      # 移動先店舗の存在確認
      destination_store = Store.find_by(id: destination_store_id, active: true)
      unless destination_store
        flash[:alert] = "指定された移動先店舗が見つかりません"
        redirect_to request_transfer_form_store_inventory_path(@inventory) and return
      end

      # TODO: 🟡 Phase 4（重要）- 移動申請ワークフローの実装
      # 優先度: 高（店舗間連携強化）
      # 実装内容:
      #   - InterStoreTransferモデルでの申請作成
      #   - 移動先店舗への通知機能
      #   - 承認待ち・承認済み・却下のステータス管理
      #   - メール通知・プッシュ通知連携
      # 期待効果: 店舗間の効率的な在庫調整、顧客満足度向上
      begin
        ActiveRecord::Base.transaction do
          # 移動申請の作成
          transfer = InterStoreTransfer.create!(
            inventory: @inventory,
            source_store: current_store,
            destination_store: destination_store,
            quantity: quantity,
            status: "pending",
            reason: reason,
            notes: notes,
            requested_by: current_store_user,
            requested_at: Time.current
          )

          # TODO: 移動先店舗への通知
          # NotificationService.notify_transfer_request(transfer)

          flash[:success] = "移動申請を送信しました（#{destination_store.name}宛、#{quantity}個）"
        end

        redirect_to store_inventory_path(@inventory)

      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "移動申請エラー: #{e.message}"
        flash[:alert] = "移動申請に失敗しました: #{e.message}"
        redirect_to request_transfer_form_store_inventory_path(@inventory)
      end
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
      # セキュリティ: ParameterSanitizationモジュールで統一処理
      allowed_columns = %w[inventories.name inventories.sku store_inventories.quantity store_inventories.safety_stock_level]

      sanitize_sort_column(params[:sort], allowed_columns)
    end

    def sort_direction
      # CLAUDE.md準拠: 統一されたサニタイゼーション
      sanitize_sort_direction(params[:direction])
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
      # CLAUDE.md準拠: 統一されたサニタイゼーション
      if search_params[:name_cont].present?
        query = sanitize_search_query(search_params[:name_cont])
        scope = scope.where("inventories.name LIKE ?", "%#{query}%") if query.present?
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

      # 在庫数範囲フィルター
      if search_params[:quantity_gteq].present? || search_params[:quantity_lteq].present?
        min = search_params[:quantity_gteq]&.to_i
        max = search_params[:quantity_lteq]&.to_i

        if min && max
          scope = scope.where("store_inventories.quantity BETWEEN ? AND ?", min, max)
        elsif min
          scope = scope.where("store_inventories.quantity >= ?", min)
        elsif max
          scope = scope.where("store_inventories.quantity <= ?", max)
        end
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
      require "csv"

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

    # ============================================
    # 🔧 CLAUDE.md準拠: セキュリティ・認証メソッド
    # ============================================

    # 店舗ユーザー認証の確認
    # 在庫操作系アクション（調整、移動申請）で必須
    def ensure_authenticated_store_user
      unless store_user_signed_in? && current_store
        flash[:alert] = "この操作を行うにはログインが必要です"
        redirect_to store_selection_path and return
      end
    end

    # QAレビュー対応: 在庫アクセス認可の確認
    def authorize_inventory_access
      return unless @inventory.present?

      # 在庫の店舗スコープ検証
      verify_resource_store_scope
    end

    # 特定リソースの店舗スコープ検証
    def verify_resource_store_scope
      # 認証されていない場合はスキップ（公開アクセス）
      return unless store_user_signed_in? && current_store

      # 在庫が現在の店舗に属するか確認
      if @inventory.present?
        store_inventory = current_store.store_inventories.find_by(inventory: @inventory)
        unless store_inventory
          handle_unauthorized_access(:inventory_not_in_store)
        end
      end
    end
  end
end

# ============================================
# TODO: Phase 4以降の拡張予定 - CSV機能の更なる発展
# ============================================

# 🔴 Phase 4緊急（1週間以内）- 管理者用CSV機能の横展開
# 優先度: 緊急（機能統一性確保）
# 実装内容:
#   - AdminControllers::StoreInventoriesController への同様のCSV機能追加
#   - AdminControllers::InventoriesController への全体CSV機能追加
#   - 管理者権限による詳細情報（仕入価格、マージン等）の出力
# 理由: 店舗・管理者間の機能一貫性確保とデータ分析ニーズ対応
# 期待効果: 全レベルでのデータ出力統一、業務効率向上

# 🟡 Phase 5重要（2週間以内）- CSV機能の拡張
# 優先度: 重要（ユーザビリティ向上）
# 実装内容:
#   - カスタムCSV出力項目選択機能
#   - 期間指定による履歴データ出力
#   - Excel形式(.xlsx)でのエクスポート対応
#   - 定期自動出力・メール配信機能
# 理由: ユーザーの多様なデータ活用ニーズへの対応
# 期待効果: データ分析精度向上、レポート作成の自動化

# 🟢 Phase 6推奨（1ヶ月以内）- 高度なデータエクスポート機能
# 優先度: 推奨（高度機能）
# 実装内容:
#   - 複数店舗横断でのデータ統合出力
#   - グラフ・チャート付きレポート生成
#   - API経由での外部システム連携
#   - データ可視化ダッシュボード機能
# 理由: データドリブン経営の支援とビジネスインテリジェンス強化
# 期待効果: 経営判断の高度化、競合優位性の確立

# ============================================
# TODO: 従来の機能拡張予定
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
