# frozen_string_literal: true

module AdminControllers
  # 店舗管理用コントローラ
  # Phase 2: Multi-Store Management
  class StoresController < BaseController
    include DatabaseAgnosticSearch  # 🔧 MySQL/PostgreSQL両対応検索機能

    before_action :set_store, only: [ :show, :edit, :update, :destroy, :dashboard ]
    before_action :ensure_multi_store_permissions, except: [ :index, :dashboard ]

    def index
      # 🔍 パフォーマンス最適化: Counter Cacheを活用（CLAUDE.md準拠）
      # メタ認知: includesは不要、viewでCounter Cacheメソッドのみ使用
      @stores = Store.active
                    .page(params[:page])
                    .per(20)

      # 🔢 統計情報の効率的計算（SQL集約関数使用）
      @stats = calculate_store_overview_stats

      # 🔍 検索・フィルタリング機能
      apply_store_filters if params[:search].present? || params[:filter].present?
    end

    def show
      # 🔍 店舗詳細情報: 関連データ事前ロード
      @store_inventories = @store.store_inventories
                                 .includes(:inventory)
                                 .page(params[:page])
                                 .per(50)

      # 📊 店舗固有統計
      @store_stats = calculate_store_detailed_stats(@store)

      # 📋 最近の移動履歴
      @recent_transfers = load_recent_transfers(@store)
    end

    def new
      authorize_headquarters_admin!
      @store = Store.new
    end

    def create
      authorize_headquarters_admin!
      @store = Store.new(store_params)

      if @store.save
        redirect_to admin_store_path(@store),
                    notice: "店舗「#{@store.display_name}」が正常に作成されました。"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize_store_management!(@store)
    end

    def update
      authorize_store_management!(@store)

      if @store.update(store_params)
        redirect_to admin_store_path(@store),
                    notice: "店舗「#{@store.display_name}」が正常に更新されました。"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize_headquarters_admin!

      store_name = @store.display_name

      # CLAUDE.md準拠: メタ認知的エラーハンドリング
      # TODO: Phase 3 - 論理削除（ソフトデリート）の実装
      #   - 店舗は重要なマスタデータのため物理削除より論理削除推奨
      #   - 削除フラグ: deleted_at カラムの追加
      #   - 関連データの整合性保持（在庫、移動履歴）
      # 横展開: Admin, Inventoryモデルでも同様の実装検討
      begin
        if @store.destroy
          redirect_to admin_stores_path,
                      notice: "店舗「#{store_name}」が正常に削除されました。"
        else
          handle_destroy_error(store_name)
        end
      rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError => e
        # 依存関係による削除制限（管理者、在庫、移動など）
        Rails.logger.warn "Store deletion restricted: #{e.message}, store_id: #{@store.id}"

        # CLAUDE.md準拠: ユーザーフレンドリーなエラーメッセージ（日本語化）
        # メタ認知: 店舗削除の場合、具体的な関連データを明示してユーザーの理解を促進
        error_message = case e.message
        when /admin.*exist/i, /dependent.*admin.*exist/i
          "この店舗には管理者アカウントが紐付けられているため削除できません。\n\n削除手順：\n1. 該当管理者を他店舗に移動、または削除\n2. 店舗の削除を再実行"
        when /inventory.*exist/i, /dependent.*inventory.*exist/i
          "この店舗には在庫データが存在するため削除できません。\n\n削除手順：\n1. 在庫の他店舗への移動\n2. または在庫のアーカイブ化\n3. 店舗の削除を再実行"
        when /transfer.*exist/i, /dependent.*transfer.*exist/i
          "この店舗には移動履歴が記録されているため削除できません。\n監査上、移動履歴の保護が必要です。\n\n代替案：店舗を「非アクティブ」状態に変更してください。"
        when /Cannot delete.*dependent.*exist/i
          "この店舗には関連する記録が存在するため削除できません。\n関連データ：管理者、在庫、移動履歴、監査ログなど\n\n詳細確認後、関連データの整理を行ってください。"
        else
          "関連するデータ（管理者、在庫、移動履歴など）が存在するため削除できません。"
        end

        handle_destroy_error(store_name, error_message)
      rescue => e
        Rails.logger.error "Store deletion failed: #{e.message}, store_id: #{@store.id}"
        handle_destroy_error(store_name, "削除中にエラーが発生しました。")
      end
    end

    # 🏪 店舗個別ダッシュボード
    def dashboard
      # 🔐 権限チェック: 店舗管理者は自店舗のみ、本部管理者は全店舗
      authorize_store_view!(@store)

      # 📊 店舗ダッシュボード統計（設計文書参照）
      @dashboard_stats = calculate_store_dashboard_stats(@store)

      # ⚠️ 低在庫アラート
      @low_stock_items = @store.store_inventories
                               .joins(:inventory)
                               .where("store_inventories.quantity <= store_inventories.safety_stock_level")
                               .includes(:inventory)
                               .limit(10)

      # 📈 移動申請状況
      @pending_transfers = @store.outgoing_transfers
                                 .pending
                                 .includes(:destination_store, :inventory, :requested_by)
                                 .limit(5)

      # 📊 期間別パフォーマンス
      @weekly_performance = calculate_weekly_performance(@store)
    end

    private

    def set_store
      # CLAUDE.md準拠: パフォーマンス最適化 - アクション別に必要な関連データのみを読み込み
      # メタ認知: show/editアクションは関連データが必要、update/destroyは基本情報のみで十分
      case action_name
      when "show", "edit", "dashboard"
        # 詳細表示・編集・ダッシュボード: 関連データを含む包括的なデータを読み込み
        @store = Store.includes(:store_inventories, :admins, :outgoing_transfers, :incoming_transfers)
                      .find(params[:id])
      else
        # update, destroy: 基本的なStoreデータのみで十分
        # パフォーマンス向上: 不要なJOINとデータ読み込みを回避
        @store = Store.find(params[:id])
      end
    end

    def store_params
      params.require(:store).permit(
        :name, :code, :store_type, :region, :address,
        :phone, :email, :manager_name, :active
      )
    end

    # ============================================
    # 🔐 認可メソッド（ロールベースアクセス制御）
    # ============================================

    def ensure_multi_store_permissions
      unless current_admin.can_access_all_stores? || current_admin.can_manage_store?(@store)
        redirect_to admin_root_path,
                    alert: "この操作を実行する権限がありません。"
      end
    end

    def authorize_headquarters_admin!
      unless current_admin.headquarters_admin?
        redirect_to admin_root_path,
                    alert: "本部管理者のみ実行可能な操作です。"
      end
    end

    def authorize_store_management!(store)
      unless current_admin.can_manage_store?(store)
        redirect_to admin_root_path,
                    alert: "この店舗を管理する権限がありません。"
      end
    end

    def authorize_store_view!(store)
      unless current_admin.can_view_store?(store)
        redirect_to admin_root_path,
                    alert: "この店舗を閲覧する権限がありません。"
      end
    end

    # ============================================
    # 📊 統計計算メソッド（パフォーマンス最適化）
    # ============================================

    # CLAUDE.md準拠: 削除エラー時の共通処理
    # メタ認知: InventoriesControllerと同様のパターン適用
    def handle_destroy_error(store_name, message = nil)
      error_message = message || @store.errors.full_messages.join("、")

      redirect_to admin_store_path(@store),
                  alert: "店舗「#{store_name}」の削除に失敗しました: #{error_message}"
    end

    def calculate_store_overview_stats
      {
        total_stores: Store.active.count,
        total_inventories: StoreInventory.joins(:store).where(stores: { active: true }).count,
        total_inventory_value: StoreInventory.joins(:store, :inventory)
                                           .where(stores: { active: true })
                                           .sum("store_inventories.quantity * inventories.price"),
        low_stock_stores: Store.active
                              .joins(:store_inventories)
                              .where("store_inventories.quantity <= store_inventories.safety_stock_level")
                              .distinct
                              .count,
        pending_transfers: InterStoreTransfer.pending.count,
        completed_transfers_today: InterStoreTransfer.completed
                                                   .where(completed_at: Date.current.all_day)
                                                   .count
      }
    end

    def calculate_store_detailed_stats(store)
      {
        # Counter Cache使用でN+1クエリ完全解消
        total_items: store.store_inventories_count,
        total_value: store.total_inventory_value,
        low_stock_count: store.low_stock_items_count,
        out_of_stock_count: store.out_of_stock_items_count,
        available_items_count: store.available_items_count,
        # Counter Cache使用でN+1クエリ完全解消
        pending_outgoing: store.pending_outgoing_transfers_count,
        pending_incoming: store.pending_incoming_transfers_count,
        transfers_this_month: store.outgoing_transfers
                                  .where(requested_at: 1.month.ago..Time.current)
                                  .count
      }
    end

    def calculate_store_dashboard_stats(store)
      # Phase 2: Store Dashboard統計（設計ドキュメント参照）
      store_stats = StoreInventory.store_summary(store)

      store_stats.merge({
        inventory_turnover_rate: store.inventory_turnover_rate,
        transfers_completed_today: store.outgoing_transfers
                                       .completed
                                       .where(completed_at: Date.current.all_day)
                                       .count,
        average_transfer_time: calculate_average_transfer_time(store),
        efficiency_score: calculate_store_efficiency_score(store)
      })
    end

    def calculate_weekly_performance(store)
      # 📈 週間パフォーマンス分析
      # TODO: 🟡 Phase 3（中）- groupdate gem導入で日別集計機能強化
      # 優先度: 中（分析機能の詳細化）
      # 実装内容: gem "groupdate" 追加後、group_by_day(:requested_at).count での日別分析
      # 期待効果: より詳細な週間トレンド分析、グラフ表示対応
      # 関連: app/controllers/admin_controllers/inter_store_transfers_controller.rb でも同様対応
      {
        outgoing_transfers_count: store.outgoing_transfers
                                      .where(requested_at: 1.week.ago..Time.current)
                                      .count,
        incoming_transfers_count: store.incoming_transfers
                                      .where(requested_at: 1.week.ago..Time.current)
                                      .count,
        weekly_trend: calculate_weekly_trend_summary(store),
        inventory_changes: calculate_inventory_changes(store)
      }
    end

    def load_recent_transfers(store)
      # 📋 最近の移動履歴（出入庫両方）
      outgoing = store.outgoing_transfers.recent.limit(3)
      incoming = store.incoming_transfers.recent.limit(3)

      (outgoing + incoming).sort_by(&:requested_at).reverse.first(5)
    end

    def apply_store_filters
      # 🔍 検索・フィルタリング処理（CLAUDE.md準拠: MySQL/PostgreSQL両対応）
      # 🔧 修正: ILIKE → DatabaseAgnosticSearch による適切な検索実装
      # メタ認知: PostgreSQL前提のILIKEをMySQL対応のLIKEに統一
      if params[:search].present?
        sanitized_search = sanitize_search_term(params[:search])

        # データベース非依存の複数カラム検索
        search_columns = [ "stores.name", "stores.code", "stores.region" ]
        @stores = search_across_columns(@stores, search_columns, sanitized_search)
      end

      if params[:filter].present?
        case params[:filter]
        when "pharmacy"
          @stores = @stores.pharmacy
        when "warehouse"
          @stores = @stores.warehouse
        when "headquarters"
          @stores = @stores.headquarters
        when "low_stock"
          @stores = @stores.joins(:store_inventories)
                          .where("store_inventories.quantity <= store_inventories.safety_stock_level")
                          .distinct
        end
      end
    end

    # ============================================
    # 🔧 ヘルパーメソッド（Phase 3で詳細化予定）
    # ============================================

    def calculate_average_transfer_time(store)
      # TODO: 🟡 Phase 3（中）- 移動時間分析機能の詳細実装
      # 優先度: 中（ダッシュボード価値向上）
      # 実装内容: 移動元・移動先別時間分析、ボトルネック特定
      # 期待効果: 移動プロセス最適化による効率向上
      completed_transfers = store.outgoing_transfers.completed.limit(10)
      return 0 if completed_transfers.empty?

      total_time = completed_transfers.sum(&:processing_time)
      (total_time / completed_transfers.count / 1.hour).round(1)
    end

    def calculate_store_efficiency_score(store)
      # TODO: 🟡 Phase 3（中）- 店舗効率スコア算出アルゴリズム
      # 優先度: 中（KPI可視化）
      # 実装内容: 在庫回転率、移動承認率、在庫切れ頻度の複合指標
      # 期待効果: 店舗パフォーマンス比較・改善指標提供
      base_score = 50

      # 在庫回転率ボーナス
      turnover_bonus = [ store.inventory_turnover_rate * 10, 30 ].min

      # 低在庫ペナルティ
      low_stock_penalty = store.low_stock_items_count * 2

      [ (base_score + turnover_bonus - low_stock_penalty), 0 ].max.round
    end

    def calculate_weekly_trend_summary(store)
      # 📊 週間トレンドのサマリー計算（groupdate gem無しでの代替実装）
      week_ago = 1.week.ago
      two_weeks_ago = 2.weeks.ago

      current_week_outgoing = store.outgoing_transfers
                                  .where(requested_at: week_ago..Time.current)
                                  .count
      previous_week_outgoing = store.outgoing_transfers
                                   .where(requested_at: two_weeks_ago..week_ago)
                                   .count

      current_week_incoming = store.incoming_transfers
                                  .where(requested_at: week_ago..Time.current)
                                  .count
      previous_week_incoming = store.incoming_transfers
                                   .where(requested_at: two_weeks_ago..week_ago)
                                   .count

      {
        outgoing_trend: calculate_trend_percentage(current_week_outgoing, previous_week_outgoing),
        incoming_trend: calculate_trend_percentage(current_week_incoming, previous_week_incoming),
        is_increasing: current_week_outgoing > previous_week_outgoing
      }
    end

    def calculate_trend_percentage(current, previous)
      return 0.0 if previous.zero?
      ((current - previous).to_f / previous * 100).round(1)
    end

    def calculate_inventory_changes(store)
      # TODO: 🟢 Phase 4（推奨）- 在庫変動分析の高度化
      # 優先度: 低（現在の実装で基本要求は満たしている）
      # 実装内容: 機械学習による需要予測、季節変動分析
      # 期待効果: 予測的在庫管理、自動補充提案
      {}
    end

    # ============================================
    # TODO: Phase 2以降で実装予定の機能
    # ============================================
    # 1. 🔴 店舗間比較レポート機能
    #    - 売上、在庫効率、移動頻度の横断比較
    #    - ベンチマーキング機能
    #
    # 2. 🟡 店舗設定カスタマイズ機能
    #    - 安全在庫レベル一括設定
    #    - 移動承認フローのカスタマイズ
    #
    # 3. 🟢 地理的分析機能
    #    - 店舗間距離を考慮した移動コスト計算
    #    - 最適配送ルート提案
  end
end
