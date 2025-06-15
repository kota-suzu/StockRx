# frozen_string_literal: true

class InventoriesController < ApplicationController
  include ErrorHandlers

  before_action :authenticate_admin!
  before_action :set_inventory, only: %i[show edit update destroy]

  # GET /inventories
  def index
    @search_form = InventorySearchForm.new(search_params.except(:page))

    if @search_form.valid? && @search_form.has_search_conditions?
      # 🔍 パフォーマンス最適化: SearchQueryサービスで条件付きincludesを適用
      # Counter Cacheがあるため、不要なincludesは除去（Bullet警告解消）
      # 関連: app/decorators/inventory_decorator.rb でCounter Cache優先使用
      @inventories_raw = @search_form.search.page(params[:page])
    elsif @search_form.has_search_conditions?
      # 検索条件があるがバリデーションエラーの場合
      flash.now[:alert] = @search_form.errors.full_messages.join(", ")
      # Counter Cacheで十分なため、includesは不要
      @inventories_raw = Inventory.page(params[:page])
    else
      # デフォルト表示: Counter Cacheで十分なため、includesは不要
      @inventories_raw = Inventory.page(params[:page])
    end

    # TODO: 🟢 Phase 4（推奨）- 大規模データ対応時の追加最適化
    # 優先度: 低（現在の実装で十分）
    # 実装内容: 10万件以上のデータでのページング最適化、メモリ効率改善
    # 期待効果: 大規模データセットでの安定したパフォーマンス維持

    # デコレートはKaminariメソッドにアクセスした後に実行
    @inventories = @inventories_raw.decorate

    @show_advanced = @search_form.advanced_search || @search_form.complex_search_required?

    respond_to do |format|
      format.html # Turbo Frame 対応
      format.json { render json: @inventories.map(&:as_json_with_decorated) }
      format.turbo_stream # 必要に応じて実装
    end
  end

  # GET /inventories/1
  def show
    respond_to do |format|
      format.html
      format.json { render json: @inventory.as_json_with_decorated }
    end
  end

  # GET /inventories/new
  def new
    @inventory = Inventory.new
  end

  # GET /inventories/1/edit
  def edit
  end

  # POST /inventories
  def create
    @inventory = Inventory.new(inventory_params)

    if @inventory.save
      respond_to do |format|
        format.html { redirect_to inventory_path(@inventory), notice: "在庫が正常に登録されました。" }
        format.json { render json: @inventory.decorate.as_json_with_decorated, status: :created }
        format.turbo_stream { flash.now[:notice] = "在庫が正常に登録されました。" }
      end
    else
      respond_to do |format|
        format.html {
          flash.now[:alert] = "入力内容に問題があります"
          render :new, status: :unprocessable_entity
        }
        format.json {
          error_response = {
            code: "validation_error",
            message: "入力内容に問題があります",
            details: @inventory.errors.full_messages
          }
          render json: error_response, status: :unprocessable_entity
        }
        format.turbo_stream { render :form_update, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /inventories/1
  def update
    if @inventory.update(inventory_params)
      respond_to do |format|
        format.html { redirect_to inventory_path(@inventory), notice: "在庫が正常に更新されました。" }
        format.json { render json: @inventory.decorate.as_json_with_decorated }
        format.turbo_stream { flash.now[:notice] = "在庫が正常に更新されました。" }
      end
    else
      respond_to do |format|
        format.html {
          flash.now[:alert] = "入力内容に問題があります"
          render :edit, status: :unprocessable_entity
        }
        format.json {
          error_response = {
            code: "validation_error",
            message: "入力内容に問題があります",
            details: @inventory.errors.full_messages
          }
          render json: error_response, status: :unprocessable_entity
        }
        format.turbo_stream { render :form_update, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /inventories/1
  def destroy
    @inventory.destroy!

    respond_to do |format|
      format.html { redirect_to inventories_path, notice: "在庫が正常に削除されました。", status: :see_other }
      format.json { head :no_content }
      format.turbo_stream { flash.now[:notice] = "在庫が正常に削除されました。" }
    end
  end

  # TODO: Phase 3実装予定 - 高度なCSVインポート機能（優先度：高）
  # 1. インポートプレビュー機能
  #    - CSV内容の事前確認
  #    - バリデーションエラーの事前表示
  #    - インポート前の最終確認画面
  #
  # 2. 一括更新オプション
  #    - 既存データの更新・挿入選択機能
  #    - 重複データの処理方法選択
  #    - 価格・在庫数の自動調整機能
  #
  # 3. 詳細ログ・レポート機能
  #    - インポート結果の詳細レポート
  #    - エラー内容の具体的な説明
  #    - 修正提案機能
  # def import_with_preview
  #   result = Inventory.import_from_csv_with_preview(params[:file])
  #   render json: { preview: result[:preview], errors: result[:errors] }
  # end

  # TODO: Phase 4実装予定 - バーコード統合機能（優先度：中）
  # 1. バーコードスキャン機能
  #    - リアルタイムバーコード読み取り
  #    - 在庫の即座検索・表示
  #    - モバイル端末対応
  #
  # 2. 在庫管理効率化
  #    - 入出庫時のバーコードスキャン
  #    - 棚卸業務の効率化
  #    - 誤操作防止機能
  # def scan_barcode
  #   @inventory = Inventory.find_by_barcode(params[:barcode_data])
  #   render json: @inventory.as_json_with_location_info if @inventory
  # end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_inventory
      @inventory = Inventory.includes(:batches, :inventory_logs, :shipments, :receipts).find(params[:id]).decorate
    end

    # Only allow a list of trusted parameters through.
    def inventory_params
      params.require(:inventory).permit(:name, :quantity, :price, :status, :category, :unit, :minimum_stock)
    end

    # 検索パラメータの許可（フォームオブジェクト対応）
    def search_params
      params.permit(
        # 基本検索フィールド
        :name, :q, :status, :min_price, :max_price, :min_quantity, :max_quantity,
        # 日付関連
        :created_from, :created_to, :updated_from, :updated_to,
        # バッチ関連
        :lot_code, :expires_before, :expires_after, :expiring_days,
        # 高度な検索オプション
        :search_type, :include_archived, :stock_filter, :low_stock_threshold,
        # 従来の互換性パラメータ
        :low_stock, :advanced_search,
        # 出荷・入荷関連
        :shipment_status, :destination, :receipt_status, :source,
        # 新機能
        :expiring_soon, :recently_updated, :updated_days,
        # ページング・ソート
        :page, :per_page, :sort_field, :sort, :direction,
        # カスタム条件（将来拡張用）
        custom_conditions: [],
        or_conditions: [],
        complex_condition: {}
      )
    end
end
