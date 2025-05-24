class InventoryLogsController < ApplicationController
  before_action :set_inventory, only: [ :index, :show ]
  PER_PAGE = 20  # 1ページあたりの表示件数

  # 特定の在庫アイテムのログ一覧を表示
  def index
    base_query = @inventory ? @inventory.inventory_logs.recent : InventoryLog.recent

    # 日付範囲フィルター（不正な日付形式はスキップ）
    begin
      if params[:start_date].present? || params[:end_date].present?
        start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
        end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
        base_query = base_query.by_date_range(start_date, end_date)
      end
    rescue Date::Error => e
      # 不正な日付形式の場合はflashメッセージを表示してフィルターをスキップ
      flash.now[:alert] = "日付の形式が正しくありません。フィルターは適用されませんでした。"
      Rails.logger.info("Invalid date format in inventory logs filter: #{e.message}")
    end

    @logs = base_query.includes(:inventory).page(params[:page]).per(PER_PAGE)

    respond_to do |format|
      format.html
      format.json { render json: @logs }
      format.csv { send_data InventoryLog.generate_csv(base_query), filename: "inventory_logs-#{Date.today}.csv" }
    end
  end

  # 特定のログ詳細を表示
  def show
    @log = InventoryLog.find(params[:id])  # RecordNotFoundはErrorHandlersが404で処理
  end

  # システム全体のログを表示
  def all
    @logs = InventoryLog.includes(:inventory).recent.page(params[:page]).per(PER_PAGE)
    render :index
  end

  # 特定の操作種別のログを表示
  def by_operation
    @operation_type = params[:operation_type]
    @logs = InventoryLog.by_operation(@operation_type).includes(:inventory).recent.page(params[:page]).per(PER_PAGE)

    render :index
  end

  private

  def set_inventory
    @inventory = Inventory.find(params[:inventory_id]) if params[:inventory_id]
  end
end
