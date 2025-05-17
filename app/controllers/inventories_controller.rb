# frozen_string_literal: true

class InventoriesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_inventory, only: %i[show edit update destroy]

  # GET /inventories
  def index
    @inventories = SearchQuery.call(params).includes(:batches).decorate

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

    respond_to do |format|
      if @inventory.save
        format.html { redirect_to inventory_path(@inventory), notice: "在庫が正常に登録されました。" }
        format.json { render json: @inventory.decorate.as_json_with_decorated, status: :created }
        format.turbo_stream { flash.now[:notice] = "在庫が正常に登録されました。" }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { errors: @inventory.errors.full_messages }, status: :unprocessable_entity }
        format.turbo_stream { render :form_update, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /inventories/1
  def update
    respond_to do |format|
      if @inventory.update(inventory_params)
        format.html { redirect_to inventory_path(@inventory), notice: "在庫が正常に更新されました。" }
        format.json { render json: @inventory.decorate.as_json_with_decorated }
        format.turbo_stream { flash.now[:notice] = "在庫が正常に更新されました。" }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { errors: @inventory.errors.full_messages }, status: :unprocessable_entity }
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

  # TODO: CSV一括インポート機能
  # def import
  #   result = Inventory.import_from_csv(params[:file])
  #   redirect_to inventories_path, notice: "#{result[:valid_count]}件のデータがインポートされました。#{result[:invalid_records].size}件の無効なデータがありました。"
  # end

  # TODO: バーコードスキャンによる在庫検索機能
  # def scan
  #   @inventory = Inventory.find_by_barcode(params[:barcode_data])
  #   redirect_to inventory_path(@inventory)
  # end

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
