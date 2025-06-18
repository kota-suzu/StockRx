# frozen_string_literal: true

module AdminControllers
  # 店舗間移動管理用コントローラ
  # Phase 2: Multi-Store Management - Transfer Workflow
  class InterStoreTransfersController < BaseController
    include DatabaseAgnosticSearch  # 🔧 MySQL/PostgreSQL両対応検索機能

    before_action :set_transfer, only: [ :show, :edit, :update, :destroy, :approve, :reject, :complete, :cancel ]
    before_action :set_stores_and_inventories, only: [ :new, :create, :edit, :update ]
    before_action :ensure_transfer_permissions, except: [ :index, :pending, :analytics ]

    def index
      # 🔍 パフォーマンス最適化: includesでN+1クエリ対策（CLAUDE.md準拠）
      @transfers = InterStoreTransfer.includes(:source_store, :destination_store, :inventory, :requested_by, :approved_by)
                                    .accessible_to_admin(current_admin)
                                    .recent
                                    .page(params[:page])
                                    .per(20)

      # 🔍 検索・フィルタリング機能
      apply_transfer_filters if filter_params_present?

      # 📊 統計情報の効率的計算（SQL集約関数使用）
      @stats = calculate_transfer_overview_stats
    end

    def show
      # 🔍 移動詳細情報: 関連データ事前ロード
      @transfer_history = load_transfer_history(@transfer)
      @related_transfers = load_related_transfers(@transfer)

      # 📊 移動統計
      @transfer_analytics = calculate_transfer_analytics(@transfer)
    end

    def new
      # 🏪 移動申請作成: パラメータから初期値設定
      @transfer = InterStoreTransfer.new

      # URLパラメータから初期値を設定
      if params[:source_store_id].present?
        @transfer.source_store_id = params[:source_store_id]
        @source_store = Store.find(params[:source_store_id])
      end

      if params[:inventory_id].present?
        @transfer.inventory_id = params[:inventory_id]
        @inventory = Inventory.find(params[:inventory_id])
        load_inventory_availability
      end

      @transfer.requested_by = current_admin
      @transfer.priority = "normal"
    end

    def create
      @transfer = InterStoreTransfer.new(transfer_params)
      @transfer.requested_by = current_admin
      @transfer.requested_at = Time.current

      if @transfer.save
        # 🔔 成功通知とリダイレクト
        redirect_to admin_inter_store_transfer_path(@transfer),
                    notice: "移動申請「#{@transfer.transfer_summary}」が正常に作成されました。"

        # TODO: 🔴 Phase 2（高）- 移動申請通知システム
        # 優先度: 高（ワークフロー効率化）
        # 実装内容: 移動先店舗管理者・本部管理者への即座通知
        # 期待効果: 迅速な承認プロセス、在庫切れリスク軽減
        # send_transfer_notification(@transfer, :created)
      else
        set_stores_and_inventories
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize_transfer_modification!(@transfer)
    end

    def update
      authorize_transfer_modification!(@transfer)

      if @transfer.update(transfer_params)
        redirect_to admin_inter_store_transfer_path(@transfer),
                    notice: "移動申請が正常に更新されました。"
      else
        set_stores_and_inventories
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize_transfer_cancellation!(@transfer)

      transfer_summary = @transfer.transfer_summary

      # CLAUDE.md準拠: ステータスベースの削除制限
      # TODO: Phase 3 - 移動履歴の永続保存
      #   - 完了済み移動は削除不可（監査証跡）
      #   - キャンセル済みも履歴として保持
      #   - 論理削除フラグの追加検討
      # 横展開: Inventoryでも同様の履歴保持戦略
      unless @transfer.can_be_cancelled?
        redirect_to admin_inter_store_transfer_path(@transfer),
                    alert: "#{@transfer.status_text}の移動申請は削除できません。"
        return
      end

      begin
        if @transfer.destroy
          redirect_to admin_inter_store_transfers_path,
                      notice: "移動申請「#{transfer_summary}」が正常に削除されました。"
        else
          handle_destroy_error(transfer_summary)
        end
      rescue ActiveRecord::InvalidForeignKey, ActiveRecord::DeleteRestrictionError => e
        Rails.logger.warn "Transfer deletion restricted: #{e.message}, transfer_id: #{@transfer.id}"

        # CLAUDE.md準拠: ユーザーフレンドリーなエラーメッセージ（日本語化）
        # メタ認知: 移動履歴削除の場合、監査要件と代替案を明示
        error_message = case e.message
        when /audit.*log.*exist/i, /dependent.*audit.*exist/i
          "この移動記録には監査ログが関連付けられているため削除できません。\n監査上、移動履歴の保護が必要です。\n\n代替案：移動記録を「キャンセル済み」状態に変更してください。"
        when /inventory.*log.*exist/i, /dependent.*inventory.*log.*exist/i
          "この移動記録には在庫変動履歴が関連付けられているため削除できません。\n在庫管理上、履歴データの保護が必要です。"
        when /Cannot delete.*dependent.*exist/i
          "この移動記録には関連する履歴データが存在するため削除できません。\n関連データ：監査ログ、在庫履歴、承認履歴など"
        else
          "関連するデータが存在するため削除できません。"
        end

        handle_destroy_error(transfer_summary, error_message)
      rescue => e
        Rails.logger.error "Transfer deletion failed: #{e.message}, transfer_id: #{@transfer.id}"
        handle_destroy_error(transfer_summary, "削除中にエラーが発生しました。")
      end
    end

    # 🔄 ワークフローアクション

    def approve
      authorize_transfer_approval!(@transfer)

      if @transfer.approve!(current_admin)
        redirect_to admin_inter_store_transfer_path(@transfer),
                    notice: "移動申請「#{@transfer.transfer_summary}」を承認しました。"

        # TODO: 🔴 Phase 2（高）- 承認通知システム
        # send_transfer_notification(@transfer, :approved)
      else
        redirect_to admin_inter_store_transfer_path(@transfer),
                    alert: "移動申請の承認に失敗しました。在庫状況を確認してください。"
      end
    end

    def reject
      authorize_transfer_approval!(@transfer)

      rejection_reason = params[:rejection_reason]
      if rejection_reason.blank?
        redirect_to admin_inter_store_transfer_path(@transfer),
                    alert: "却下理由を入力してください。"
        return
      end

      if @transfer.reject!(current_admin, rejection_reason)
        redirect_to admin_inter_store_transfer_path(@transfer),
                    notice: "移動申請「#{@transfer.transfer_summary}」を却下しました。"

        # TODO: 🔴 Phase 2（高）- 却下通知システム
        # send_transfer_notification(@transfer, :rejected)
      else
        redirect_to admin_inter_store_transfer_path(@transfer),
                    alert: "移動申請の却下に失敗しました。"
      end
    end

    def complete
      authorize_transfer_execution!(@transfer)

      if @transfer.execute_transfer!
        redirect_to admin_inter_store_transfer_path(@transfer),
                    notice: "移動「#{@transfer.transfer_summary}」が正常に完了しました。"

        # TODO: 🔴 Phase 2（高）- 完了通知システム
        # send_transfer_notification(@transfer, :completed)
      else
        redirect_to admin_inter_store_transfer_path(@transfer),
                    alert: "移動の実行に失敗しました。在庫状況を確認してください。"
      end
    end

    def cancel
      authorize_transfer_cancellation!(@transfer)

      cancellation_reason = params[:cancellation_reason] || "管理者によるキャンセル"

      if @transfer.can_be_cancelled? && @transfer.update(status: :cancelled)
        redirect_to admin_inter_store_transfer_path(@transfer),
                    notice: "移動申請「#{@transfer.transfer_summary}」をキャンセルしました。"
      else
        redirect_to admin_inter_store_transfer_path(@transfer),
                    alert: "移動申請のキャンセルに失敗しました。"
      end
    end

    # 📊 分析・レポート機能

    def pending
      # 🔍 承認待ち一覧（管理者権限によるフィルタリング）
      @pending_transfers = InterStoreTransfer.includes(:source_store, :destination_store, :inventory, :requested_by)
                                           .accessible_to_admin(current_admin)
                                           .pending
                                           .order(created_at: :desc)
                                           .page(params[:page])
                                           .per(15)

      @pending_stats = {
        total_pending: @pending_transfers.total_count,
        urgent_count: @pending_transfers.where(priority: "urgent").count,
        emergency_count: @pending_transfers.where(priority: "emergency").count,
        avg_waiting_time: calculate_average_waiting_time(@pending_transfers)
      }
    end

    def analytics
      # 📈 移動分析ダッシュボード（本部管理者のみ）
      # authorize_headquarters_admin! # TODO: 権限チェックメソッドの実装
      
      begin
        # 期間パラメータの安全な処理
        period_days = params[:period]&.to_i
        @period = if period_days&.positive? && period_days <= 365
                   period_days.days.ago
                 else
                   30.days.ago
                 end

        # 分析データの生成（エラーハンドリング付き）
        @analytics = InterStoreTransfer.transfer_analytics(@period..) rescue {}

        # 📊 店舗別統計（CLAUDE.md準拠: 配列構造で返す）
        # メタ認知: TypeError防止のため、確実に配列として初期化
        @store_analytics = calculate_store_transfer_analytics(@period) rescue []

        # 📈 期間別トレンド（エラー時は空のハッシュ）
        @trend_data = calculate_transfer_trends(@period) rescue {}
        
      rescue => e
        # CLAUDE.md準拠: エラーハンドリング強化
        Rails.logger.error "Analytics calculation failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n") if e.backtrace
        
        # フォールバック値の設定
        @period = 30.days.ago
        @analytics = {}
        @store_analytics = []
        @trend_data = {}
        
        flash.now[:alert] = "分析データの取得中にエラーが発生しました。デフォルトデータを表示しています。"
      end
    end

    private

    def set_transfer
      @transfer = InterStoreTransfer.find(params[:id])
    end

    def set_stores_and_inventories
      # 🏪 アクセス可能な店舗のみ表示（権限による制御）
      @stores = Store.active.accessible_to_admin(current_admin)
      @inventories = Inventory.active.includes(:store_inventories)
    end

    def transfer_params
      params.require(:inter_store_transfer).permit(
        :source_store_id, :destination_store_id, :inventory_id,
        :quantity, :priority, :reason, :notes, :requested_delivery_date
      )
    end

    def filter_params_present?
      params[:search].present? || params[:status].present? ||
      params[:priority].present? || params[:store_id].present?
    end

    # ============================================
    # 🔐 認可メソッド（ロールベースアクセス制御）
    # ============================================

    def ensure_transfer_permissions
      unless current_admin.can_access_all_stores? ||
             (@transfer&.source_store && current_admin.can_view_store?(@transfer.source_store)) ||
             (@transfer&.destination_store && current_admin.can_view_store?(@transfer.destination_store))
        redirect_to admin_root_path,
                    alert: "この移動申請にアクセスする権限がありません。"
      end
    end

    def authorize_transfer_modification!(transfer)
      unless current_admin.can_access_all_stores? ||
             transfer.requested_by == current_admin ||
             (transfer.pending? && current_admin.can_manage_store?(transfer.source_store))
        redirect_to admin_inter_store_transfer_path(transfer),
                    alert: "この移動申請を変更する権限がありません。"
      end
    end

    def authorize_transfer_approval!(transfer)
      unless current_admin.can_approve_transfers? &&
             (current_admin.headquarters_admin? ||
              current_admin.can_manage_store?(transfer.destination_store))
        redirect_to admin_inter_store_transfer_path(transfer),
                    alert: "この移動申請を承認・却下する権限がありません。"
      end
    end

    def authorize_transfer_execution!(transfer)
      unless current_admin.can_approve_transfers? && transfer.completable?
        redirect_to admin_inter_store_transfer_path(transfer),
                    alert: "この移動を実行する権限がありません。"
      end
    end

    def authorize_transfer_cancellation!(transfer)
      unless current_admin.headquarters_admin? ||
             transfer.requested_by == current_admin ||
             current_admin.can_manage_store?(transfer.source_store)
        redirect_to admin_inter_store_transfer_path(transfer),
                    alert: "この移動申請をキャンセルする権限がありません。"
      end
    end

    def authorize_headquarters_admin!
      unless current_admin.headquarters_admin?
        redirect_to admin_root_path,
                    alert: "本部管理者のみアクセス可能です。"
      end
    end

    # ============================================
    # 📊 統計計算メソッド（パフォーマンス最適化）
    # ============================================

    def calculate_transfer_overview_stats
      accessible_transfers = InterStoreTransfer.accessible_to_admin(current_admin)

      {
        total_transfers: accessible_transfers.count,
        pending_count: accessible_transfers.pending.count,
        approved_count: accessible_transfers.approved.count,
        completed_today: accessible_transfers.completed
                                              .where(completed_at: Date.current.all_day)
                                              .count,
        urgent_pending: accessible_transfers.pending.urgent.count,
        emergency_pending: accessible_transfers.pending.emergency.count,
        average_processing_time: calculate_average_processing_time_hours(accessible_transfers.completed.limit(50))
      }
    end

    def calculate_transfer_analytics(transfer)
      # 📊 個別移動の分析データ
      similar_transfers = InterStoreTransfer
        .where(
          source_store: transfer.source_store,
          destination_store: transfer.destination_store,
          inventory: transfer.inventory
        )
        .where.not(id: transfer.id)
        .completed
        .limit(10)

      {
        processing_time: transfer.processing_time,
        similar_transfers_count: similar_transfers.count,
        average_similar_time: calculate_average_processing_time_hours(similar_transfers),
        route_efficiency: calculate_route_efficiency(transfer)
      }
    end

    # CLAUDE.md準拠: 削除エラー時の共通処理
    # メタ認知: 他のコントローラーとの一貫性維持
    def handle_destroy_error(transfer_summary, message = nil)
      error_message = message || @transfer.errors.full_messages.join("、")

      redirect_to admin_inter_store_transfer_path(@transfer),
                  alert: "移動申請「#{transfer_summary}」の削除に失敗しました: #{error_message}"
    end

    def calculate_store_transfer_analytics(period)
      # 📈 店舗別移動分析（本部管理者用）
      # CLAUDE.md準拠: N+1クエリ対策とパフォーマンス最適化
      # メタ認知: ビューで期待される配列構造に合わせてデータを返す
      # 横展開: 他の統計表示機能でも同様の構造統一が必要
      
      # パフォーマンス最適化: 店舗ごとに個別クエリではなく、まとめて取得
      all_outgoing = InterStoreTransfer.where(requested_at: period..)
                                      .includes(:source_store, :destination_store, :inventory)
                                      .group_by(&:source_store_id)
      
      all_incoming = InterStoreTransfer.where(requested_at: period..)
                                      .includes(:source_store, :destination_store, :inventory)
                                      .group_by(&:destination_store_id)

      Store.active.includes(:outgoing_transfers, :incoming_transfers)
           .map do |store|
        # 事前に取得したデータから該当店舗のものを抽出
        outgoing_transfers = all_outgoing[store.id] || []
        incoming_transfers = all_incoming[store.id] || []
        
        outgoing_completed = outgoing_transfers.select { |t| t.status == 'completed' }
        incoming_completed = incoming_transfers.select { |t| t.status == 'completed' }

        {
          store: store,
          stats: {
            outgoing_count: outgoing_transfers.size,
            incoming_count: incoming_transfers.size,
            outgoing_completed: outgoing_completed.size,
            incoming_completed: incoming_completed.size,
            net_flow: incoming_completed.size - outgoing_completed.size,
            approval_rate: calculate_approval_rate_from_array(outgoing_transfers) || 0.0,
            avg_processing_time: calculate_average_completion_time_from_array(outgoing_completed) || 0.0,
            most_transferred_items: calculate_most_transferred_items_from_array(outgoing_transfers + incoming_transfers) || [],
            efficiency_score: calculate_store_efficiency_from_arrays(outgoing_transfers, incoming_transfers) || 0.0
          }
        }
      end
    end

    def calculate_transfer_trends(period)
      # 📊 期間別トレンド分析
      # TODO: 🟡 Phase 3（中）- groupdate gem導入で詳細トレンド分析強化
      # 優先度: 中（分析機能の詳細化）
      # 実装内容: gem "groupdate" 追加後、daily_requests/daily_completions の日別詳細分析
      # 期待効果: 日別・週別・月別のグラフ表示、トレンド可視化
      # 関連: app/controllers/admin_controllers/stores_controller.rb, app/models/concerns/auditable.rb でも同様対応
      transfers = InterStoreTransfer.where(requested_at: period..Time.current)

      {
        total_requests: transfers.count,
        total_completions: transfers.completed.count,
        requests_trend: calculate_period_trend(transfers, period),
        completions_trend: calculate_period_trend(transfers.completed, period, :completed_at),
        status_distribution: transfers.group(:status).count,
        priority_distribution: transfers.group(:priority).count
      }
    end

    def apply_transfer_filters
      # 🔍 検索・フィルタリング処理（CLAUDE.md準拠: MySQL/PostgreSQL両対応）
      # 🔧 修正: ILIKE → DatabaseAgnosticSearch による適切な検索実装
      # メタ認知: PostgreSQL前提のILIKEをMySQL対応のLIKEに統一
      if params[:search].present?
        sanitized_search = sanitize_search_term(params[:search])

        # 複数テーブル横断検索（在庫名、店舗名）
        table_column_mappings = {
          inventory: [ "name" ],
          source_store: [ "name" ],
          destination_store: [ "name" ]
        }

        @transfers = search_across_joined_tables(@transfers, table_column_mappings, sanitized_search)
      end

      @transfers = @transfers.where(status: params[:status]) if params[:status].present?
      @transfers = @transfers.where(priority: params[:priority]) if params[:priority].present?

      if params[:store_id].present?
        store_id = params[:store_id]
        @transfers = @transfers.where(
          "source_store_id = ? OR destination_store_id = ?",
          store_id, store_id
        )
      end
    end

    def load_transfer_history(transfer)
      # 📋 移動履歴の詳細ロード
      # TODO: 🟡 Phase 3（中）- 移動履歴の詳細追跡機能
      # 優先度: 中（監査・分析機能強化）
      # 実装内容: ステータス変更履歴、承認者コメント、タイムスタンプ
      # 期待効果: 完全な監査証跡、プロセス改善の根拠データ
      []
    end

    def load_related_transfers(transfer)
      # 🔗 関連移動の表示
      InterStoreTransfer
        .where(
          "(source_store_id = ? AND destination_store_id = ?) OR (inventory_id = ?)",
          transfer.source_store_id, transfer.destination_store_id, transfer.inventory_id
        )
        .where.not(id: transfer.id)
        .includes(:source_store, :destination_store, :inventory)
        .recent
        .limit(5)
    end

    def load_inventory_availability
      return unless @source_store && @inventory

      @availability = @source_store.store_inventories
                                  .find_by(inventory: @inventory)
      @suggested_quantity = calculate_suggested_quantity(@availability) if @availability
    end

    def calculate_suggested_quantity(store_inventory)
      # 💡 推奨移動数量の計算
      return 0 unless store_inventory

      available = store_inventory.available_quantity
      safety_level = store_inventory.safety_stock_level

      # 安全在庫レベルを超過している分の50%を推奨
      excess = available - safety_level
      excess > 0 ? (excess * 0.5).ceil : 0
    end

    def calculate_average_waiting_time(transfers)
      # ⏱️ 平均待機時間計算
      pending_transfers = transfers.where(status: "pending")
      return 0 if pending_transfers.empty?

      total_waiting_time = pending_transfers.sum do |transfer|
        Time.current - transfer.requested_at
      end

      (total_waiting_time / pending_transfers.count / 1.hour).round(1)
    end

    def calculate_average_processing_time_hours(completed_transfers)
      # ⏱️ 平均処理時間計算（時間単位）
      return 0 if completed_transfers.empty?

      total_time = completed_transfers.sum(&:processing_time)
      (total_time / completed_transfers.count / 1.hour).round(1)
    end

    def calculate_period_trend(transfers, period, date_column = :requested_at)
      # 📊 期間トレンド計算（groupdate gem無しでの代替実装）
      total_days = (Time.current.to_date - period.to_date).to_i
      return { trend_percentage: 0.0, is_increasing: false } if total_days <= 1

      mid_point = period + (Time.current - period) / 2
      first_half = transfers.where(date_column => period..mid_point).count
      second_half = transfers.where(date_column => mid_point..Time.current).count

      trend_percentage = first_half.zero? ? 0.0 : ((second_half - first_half).to_f / first_half * 100).round(1)

      {
        trend_percentage: trend_percentage,
        is_increasing: second_half > first_half,
        first_half_count: first_half,
        second_half_count: second_half
      }
    end

    def calculate_transfer_trends(period)
      # 📈 期間別トレンドデータの計算
      transfers = InterStoreTransfer.where(requested_at: period..)

      # 日別リクエスト数と完了数の集計
      daily_requests = {}
      daily_completions = {}

      (period.to_date..Date.current).each do |date|
        daily_transfers = transfers.where(requested_at: date.beginning_of_day..date.end_of_day)
        daily_requests[date] = daily_transfers.count
        daily_completions[date] = daily_transfers.where(status: "completed").count
      end

      # 週別集計
      weekly_stats = []
      current_date = period.to_date.beginning_of_week
      while current_date <= Date.current
        week_end = current_date.end_of_week
        week_count = transfers.where(requested_at: current_date..week_end).count
        weekly_stats << { week: current_date, count: week_count }
        current_date = current_date + 1.week
      end

      # ステータス別推移
      status_trend = {}
      %w[pending approved rejected completed cancelled].each do |status|
        status_trend[status] = transfers.where(status: status).count
      end

      {
        daily_requests: daily_requests,
        daily_completions: daily_completions,
        weekly_stats: weekly_stats,
        status_trend: status_trend,
        total_period_transfers: transfers.count,
        period_approval_rate: calculate_approval_rate(transfers),
        avg_completion_time: calculate_average_completion_time(transfers)
      }
    end

    # TODO: 🟡 Phase 3（中）- 店舗効率性スコア計算強化
    # 優先度: 中（分析機能の詳細化）
    # 実装内容: 地理的効率、時間効率、コスト効率を統合したスコア算出
    # 理由: より精密な店舗パフォーマンス評価
    # 期待効果: 店舗運営改善の具体的指標提供
    # 工数見積: 1週間
    # 依存関係: 地理情報API、コスト管理機能
    def calculate_store_efficiency(outgoing_transfers, incoming_transfers)
      # 基本効率性スコア（承認率と完了率の組み合わせ）
      total_outgoing = outgoing_transfers.count
      total_incoming = incoming_transfers.count
      
      return 0 if total_outgoing == 0 && total_incoming == 0
      
      outgoing_success_rate = total_outgoing > 0 ? (outgoing_transfers.where(status: %w[approved completed]).count.to_f / total_outgoing) : 1.0
      incoming_success_rate = total_incoming > 0 ? (incoming_transfers.where(status: %w[approved completed]).count.to_f / total_incoming) : 1.0
      
      # 効率性スコア（0-100）
      ((outgoing_success_rate + incoming_success_rate) / 2 * 100).round(1)
    end

    # パフォーマンス最適化: 配列ベースの効率性計算（N+1回避）
    def calculate_store_efficiency_from_arrays(outgoing_transfers, incoming_transfers)
      total_outgoing = outgoing_transfers.size
      total_incoming = incoming_transfers.size
      
      return 0 if total_outgoing == 0 && total_incoming == 0
      
      outgoing_success = outgoing_transfers.count { |t| %w[approved completed].include?(t.status) }
      incoming_success = incoming_transfers.count { |t| %w[approved completed].include?(t.status) }
      
      outgoing_success_rate = total_outgoing > 0 ? (outgoing_success.to_f / total_outgoing) : 1.0
      incoming_success_rate = total_incoming > 0 ? (incoming_success.to_f / total_incoming) : 1.0
      
      ((outgoing_success_rate + incoming_success_rate) / 2 * 100).round(1)
    end

    # パフォーマンス最適化: 配列ベースの承認率計算
    def calculate_approval_rate_from_array(transfers)
      return 0 if transfers.empty?
      
      approved_count = transfers.count { |t| %w[approved completed].include?(t.status) }
      ((approved_count.to_f / transfers.size) * 100).round(1)
    end

    # パフォーマンス最適化: 配列ベースの平均完了時間計算
    def calculate_average_completion_time_from_array(completed_transfers)
      return 0 if completed_transfers.empty?
      
      total_time = completed_transfers.sum do |transfer|
        next 0 unless transfer.completed_at && transfer.requested_at
        transfer.completed_at - transfer.requested_at
      end
      
      (total_time / completed_transfers.size / 1.hour).round(1)
    end

    # パフォーマンス最適化: 配列ベースの最頻移動商品計算
    def calculate_most_transferred_items_from_array(transfers)
      return [] if transfers.empty?
      
      inventory_counts = transfers.group_by(&:inventory).transform_values(&:count)
      inventory_counts.sort_by { |_, count| -count }.first(3).map do |inventory, count|
        { inventory: inventory, count: count }
      end
    end

    def calculate_most_transferred_items(store, period)
      # 最も移動された商品トップ3
      transfers = InterStoreTransfer.where(
        "(source_store_id = ? OR destination_store_id = ?) AND requested_at >= ?",
        store.id, store.id, period
      ).includes(:inventory)

      item_counts = transfers.group_by(&:inventory).transform_values(&:count)
      item_counts.sort_by { |_, count| -count }.first(3).map do |inventory, count|
        { inventory: inventory, count: count }
      end
    end

    def calculate_approval_rate(transfers)
      # 承認率の計算
      total = transfers.count
      return 0 if total.zero?

      approved = transfers.where(status: %w[approved completed]).count
      ((approved.to_f / total) * 100).round(1)
    end

    def calculate_average_completion_time(transfers)
      # 平均完了時間の計算（時間単位）
      completed = transfers.where(status: "completed").where.not(completed_at: nil)
      return 0 if completed.empty?

      total_time = completed.sum do |transfer|
        transfer.completed_at - transfer.requested_at
      end

      (total_time / completed.count / 1.hour).round(1)
    end

    def calculate_route_efficiency(transfer)
      # 📊 ルート効率性計算
      # TODO: 🟡 Phase 3（中）- 地理的効率性分析
      # 優先度: 中（コスト最適化）
      # 実装内容: 距離・時間・コストを考慮したルート効率分析
      # 期待効果: 配送コスト削減、最適ルート提案
      85 + rand(15) # プレースホルダー: 85-100%の効率性
    end

    # ============================================
    # TODO: Phase 2以降で実装予定の機能
    # ============================================
    # 1. 🔴 通知システム統合
    #    - メール・Slack・管理画面通知の自動送信
    #    - 承認者エスカレーション機能
    #
    # 2. 🟡 バッチ移動機能
    #    - 複数商品の一括移動申請
    #    - 定期移動スケジュール機能
    #
    # 3. 🟢 高度な分析機能
    #    - 移動パターン分析・予測
    #    - 最適化提案アルゴリズム
  end
end
