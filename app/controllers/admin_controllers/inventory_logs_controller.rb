module AdminControllers
  class InventoryLogsController < AdminControllers::BaseController
    before_action :set_inventory, only: [ :index, :show ]
    PER_PAGE = 30  # 管理画面は1ページあたりの表示件数を多めに

    # 特定の在庫アイテムのログ一覧を表示
    def index
      base_query = @inventory ? @inventory.inventory_logs.recent : InventoryLog.recent

      # 日付範囲フィルター
      if params[:start_date].present? || params[:end_date].present?
        start_date = Date.parse(params[:start_date]) rescue nil
        end_date = Date.parse(params[:end_date]) rescue nil
        base_query = base_query.by_date_range(start_date, end_date)
      end

      # ユーザーフィルター（管理者専用機能）
      if params[:user_id].present?
        base_query = base_query.where(user_id: params[:user_id])
      end

      @logs = base_query.includes(:inventory, :user).page(params[:page]).per(PER_PAGE)

      respond_to do |format|
        format.html
        format.json { render json: @logs }
        format.csv { send_data InventoryLog.generate_csv(base_query), filename: "inventory_logs-#{Date.today}.csv" }
      end
    end

    # 特定のログ詳細を表示
    def show
      @log = InventoryLog.find(params[:id])
    end

    # システム全体のログを表示
    def all
      @logs = InventoryLog.includes(:inventory, :user).recent.page(params[:page]).per(PER_PAGE)
      render :index
    end

    # 特定の操作種別のログを表示
    def by_operation
      @operation_type = params[:operation_type]
      @logs = InventoryLog.by_operation(@operation_type).includes(:inventory, :user)
        .recent.page(params[:page]).per(PER_PAGE)

      render :index
    end

    # 統計情報表示
    def stats
      # 期間指定
      if params[:period].present?
        case params[:period]
        when "today"
          @start_date = Date.today
          @end_date = Date.today
        when "yesterday"
          @start_date = Date.yesterday
          @end_date = Date.yesterday
        when "this_week"
          @start_date = Date.today.beginning_of_week
          @end_date = Date.today
        when "last_week"
          @start_date = Date.today.prev_week.beginning_of_week
          @end_date = Date.today.prev_week.end_of_week
        when "this_month"
          @start_date = Date.today.beginning_of_month
          @end_date = Date.today
        when "last_month"
          @start_date = Date.today.prev_month.beginning_of_month
          @end_date = Date.today.prev_month.end_of_month
        else
          @start_date = Date.parse(params[:start_date]) rescue (Date.today - 30.days)
          @end_date = Date.parse(params[:end_date]) rescue Date.today
        end
      else
        @start_date = Date.today - 30.days
        @end_date = Date.today
      end

      # 基本的な統計情報を取得
      @logs_in_period = InventoryLog.by_date_range(@start_date, @end_date)

      @stats = {
        total_logs: @logs_in_period.count,
        total_add: @logs_in_period.by_operation("add").count,
        total_remove: @logs_in_period.by_operation("remove").count,
        total_adjust: @logs_in_period.by_operation("adjust").count,
        net_quantity_change: @logs_in_period.sum(:delta),
        top_inventories: InventoryLog.top_inventories(@start_date, @end_date, 10),
        activity_by_day: InventoryLog.activity_by_day(@start_date, @end_date)
      }
    end

    private

    def set_inventory
      @inventory = Inventory.find(params[:inventory_id]) if params[:inventory_id]
    end
  end
end
