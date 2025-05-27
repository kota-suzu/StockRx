# frozen_string_literal: true

module Api
  module V1
    class InventoriesController < ApplicationController
      before_action :authenticate_admin!
      protect_from_forgery with: :null_session
      before_action :set_inventory, only: %i[show update destroy]

      # GET /api/v1/inventories
      def index
        @inventories = SearchQuery.call(params).includes(:batches).decorate
        render :index, formats: :json
      end

      # GET /api/v1/inventories/1
      def show
        render :show, formats: :json
      end

      # POST /api/v1/inventories
      def create
        @inventory = Inventory.new(inventory_params)

        if @inventory.save
          render :show, status: :created, formats: :json
        else
          render json: { errors: @inventory.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/inventories/1
      def update
        if @inventory.update(inventory_params)
          render :show, formats: :json
        else
          render json: { errors: @inventory.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/inventories/1
      def destroy
        @inventory.destroy!
        head :no_content
      end

      # TODO: 在庫一括取得（ページネーション対応）
      # def bulk
      #   @inventories = Inventory.includes(:batches)
      #                           .order(created_at: :desc)
      #                           .page(params[:page])
      #                           .per(params[:per_page] || 100)
      #                           .decorate
      #
      #   render :index, formats: :json
      # end

      # TODO: 在庫アラート情報取得
      # def alerts
      #   @low_stock = Inventory.where('quantity <= ?', 10).includes(:batches).decorate
      #   @expired_batches = Batch.expired.includes(:inventory).decorate
      #   @expiring_soon = Batch.expiring_soon.includes(:inventory).decorate
      #
      #   render :alerts, formats: :json
      # end

      # ============================================
      # TODO: レポート機能
      # ============================================
      # 1. 在庫レポート生成
      #    - 商品ごとの在庫数・金額レポート
      #    - ロット・期限切れ情報を含む詳細レポート
      #    - 期間別の入出庫履歴レポート
      #
      # 2. 利用状況分析
      #    - 期間別在庫推移グラフ
      #    - 在庫回転率レポート
      #    - 需要予測に基づく推奨発注数レポート
      #
      # 3. データエクスポート機能
      #    - CSV/Excel形式の出力
      #    - PDFレポート生成
      #    - データ集計とフィルタリングオプション
      #

      private

      def set_inventory
        @inventory = Inventory.find(params[:id]).decorate
      end

      def inventory_params
        params.require(:inventory).permit(:name, :quantity, :price, :status)
      end
    end
  end
end
