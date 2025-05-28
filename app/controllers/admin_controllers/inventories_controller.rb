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
      @inventories = SearchQuery.call(params).includes(:batches).decorate

      respond_to do |format|
        format.html # Turbo Frame 対応
        format.json { render json: @inventories.map(&:as_json_with_decorated) }
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

    # CSV一括インポート画面
    def import_form
      render :import
    end

    # CSV一括インポート処理
    def import
      if params[:file].blank?
        redirect_to import_form_admin_inventories_path, alert: t("inventories.import.no_file")
        return
      end

      # ファイルタイプバリデーション（事前チェック）
      uploaded_file = params[:file]
      file_extension = File.extname(uploaded_file.original_filename).downcase
      allowed_extensions = [ ".csv" ]

      unless allowed_extensions.include?(file_extension)
        error_message = "Invalid file type: #{file_extension}. Allowed types: #{allowed_extensions.join(', ')}"
        redirect_to import_form_admin_inventories_path, alert: error_message
        return
      end

      # TODO: 追加のCSVファイル形式バリデーション機能
      # - ファイルサイズ制限（例：10MB）
      # - MIME typeチェック
      # - 文字エンコーディング検証（UTF-8、Shift_JIS対応）
      # - カラム数・形式の事前検証

      # ジョブIDを生成
      job_id = SecureRandom.uuid

      begin
        # 非同期ジョブとして実行
        ImportInventoriesJob.perform_later(params[:file].path, current_admin.id, job_id)

        # ジョブIDをクエリパラメータとして渡す
        redirect_to admin_inventories_path(import_started: true, job_id: job_id),
                    notice: t("inventories.import.started")
      rescue SecurityError => e
        # セキュリティエラー（ファイルタイプ、パスなど）をキャッチ
        redirect_to import_form_admin_inventories_path, alert: e.message
      rescue StandardError => e
        # その他のエラーをキャッチ
        Rails.logger.error "CSV import failed: #{e.message}"
        redirect_to import_form_admin_inventories_path, alert: t("inventories.import.error", message: e.message)
      end
    end

    private

    # Use callbacks to share common setup or constraints between actions.
    def set_inventory
      @inventory = Inventory.find(params[:id]).decorate
    end

    # Only allow a list of trusted parameters through.
    def inventory_params
      params.require(:inventory).permit(:name, :quantity, :price, :status)
    end
  end
end
