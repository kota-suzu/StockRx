# frozen_string_literal: true

module AdminControllers
  class InventoriesController < BaseController
    before_action :set_inventory, only: %i[show edit update destroy]

    # TODO: 以下の機能実装が必要
    # - 在庫一括操作機能（一括ステータス変更、一括削除）
    # - 在庫レポート機能（月次・年次レポート、在庫回転率）
    # - 在庫アラート設定機能（最低在庫数設定、期限切れアラート）
    # - エクスポート機能（PDF、Excel、CSV）
    # - 在庫履歴・監査ログ機能
    # - APIレート制限・認証機能強化

    # GET /admin/inventories
    def index
      # Kaminariページネーション実装（50/100/200件切り替え可能）
      per_page = validate_per_page_param(params[:per_page])

      # Kaminariのページネーション情報を保持
      @inventories_raw = SearchQuery.call(params)
                                   .page(params[:page])
                                   .per(per_page)

      # デコレートはKaminariメソッドにアクセスした後に実行
      @inventories = @inventories_raw.decorate

      respond_to do |format|
        format.html # Turbo Frame 対応
        format.json {
          render json: {
            inventories: @inventories.map(&:as_json_with_decorated),
            pagination: {
              current_page: @inventories_raw.current_page,
              total_pages: @inventories_raw.total_pages,
              total_count: @inventories_raw.total_count,
              per_page: @inventories_raw.limit_value
            }
          }
        }
        format.turbo_stream # 必要に応じて実装
      end
    end

    # GET /admin/inventories/1
    def show
      respond_to do |format|
        format.html
        format.json { render json: @inventory.as_json_with_decorated }
      end
    end

    # GET /admin/inventories/new
    def new
      @inventory = Inventory.new
    end

    # GET /admin/inventories/1/edit
    def edit
    end

    # POST /admin/inventories
    def create
      @inventory = Inventory.new(inventory_params)

      respond_to do |format|
        begin
          @inventory.save!
          format.html { redirect_to admin_inventory_path(@inventory), notice: "在庫が正常に登録されました。" }
          format.json { render json: @inventory.decorate.as_json_with_decorated, status: :created }
          format.turbo_stream { flash.now[:notice] = "在庫が正常に登録されました。" }
        rescue ActiveRecord::RecordInvalid => e
          # 422エラー時の個別処理
          format.html {
            flash.now[:alert] = "入力内容に問題があります"
            render :new, status: :unprocessable_entity
          }
          format.json { render json: { errors: @inventory.errors.full_messages }, status: :unprocessable_entity }
          format.turbo_stream { render :form_update, status: :unprocessable_entity }
        end
      end
    end

    # PATCH/PUT /admin/inventories/1
    def update
      respond_to do |format|
        begin
          @inventory.update!(inventory_params)
          format.html { redirect_to admin_inventory_path(@inventory), notice: "在庫が正常に更新されました。" }
          format.json { render json: @inventory.decorate.as_json_with_decorated }
          format.turbo_stream { flash.now[:notice] = "在庫が正常に更新されました。" }
        rescue ActiveRecord::RecordInvalid => e
          # 422エラー時の個別処理
          format.html {
            flash.now[:alert] = "入力内容に問題があります"
            render :edit, status: :unprocessable_entity
          }
          format.json { render json: { errors: @inventory.errors.full_messages }, status: :unprocessable_entity }
          format.turbo_stream { render :form_update, status: :unprocessable_entity }
        end
      end
    end

    # DELETE /admin/inventories/1
    def destroy
      @inventory.destroy!

      respond_to do |format|
        format.html { redirect_to admin_inventories_path, notice: "在庫が正常に削除されました。", status: :see_other }
        format.json { head :no_content }
        format.turbo_stream { flash.now[:notice] = "在庫が正常に削除されました。" }
      end
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_inventory
      # 詳細ページで使用する関連データのみをinclude（:batchesのみ使用）
      @inventory = Inventory.includes(:batches).find(params[:id]).decorate
    end

    # Only allow a list of trusted parameters through.
    def inventory_params
      params.require(:inventory).permit(:name, :quantity, :price, :status)
    end

    # Per page パラメータの検証（50/100/200のみ許可）
    def validate_per_page_param(per_page_param)
      allowed_per_page = [ 50, 100, 200 ]
      per_page = per_page_param&.to_i || 50  # デフォルト50件

      if allowed_per_page.include?(per_page)
        per_page
      else
        50  # 不正な値の場合はデフォルトに戻す
      end
    end
  end
end
