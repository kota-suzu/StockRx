# frozen_string_literal: true

module Api
  module V1
    class InventoriesController < Api::ApiController
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
        # すでにset_inventoryで@inventoryが設定されている
        # エラーハンドリングはset_inventoryとErrorHandlersによって処理される
        render :show, formats: :json
      end

      # POST /api/v1/inventories
      def create
        # 新規在庫を作成
        @inventory = Inventory.new(inventory_params)

        # デモ用：レート制限チェック（ランダムに制限トリガー）
        if rand(100) == 1 # 1%の確率でRateLimitExceededエラー発生
          raise CustomError::RateLimitExceeded.new(
            "短時間に多くのリクエストが行われました",
            [ "30秒後に再試行してください" ]
          )
        end

        # save!はバリデーションエラーでActiveRecord::RecordInvalidが発生し、
        # ErrorHandlersが422ハンドリングしてくれる
        @inventory.save!

        # 成功時は201 Created + リソースの内容を返却
        render :show, status: :created, formats: :json
      rescue ActiveRecord::RecordInvalid => e
        # ErrorHandlersがこのエラーをハンドルするため、
        # ここでのrescueは不要だが、デモ用に追加
        raise e
      end

      # PATCH/PUT /api/v1/inventories/1
      def update
        # すでにset_inventoryで@inventoryが設定されている

        # 楽観的ロックのバージョンチェック（競合検出）
        if params[:inventory][:lock_version].present? &&
           params[:inventory][:lock_version].to_i != @inventory.lock_version

          # カスタムエラーで409 Conflictを発生
          raise CustomError::ResourceConflict.new(
            "他のユーザーがこの在庫を更新しました。最新の情報で再試行してください。",
            [ "同時編集が検出されました。画面をリロードして最新データを取得してください。" ]
          )
        end

        # update!はバリデーションエラーでActiveRecord::RecordInvalidが発生
        @inventory.update!(inventory_params)

        # 成功時は200 OK + 更新後リソースの内容を返却
        render :show, formats: :json
      end

      # DELETE /api/v1/inventories/1
      def destroy
        # すでにset_inventoryで@inventoryが設定されている

        # 物理削除ではなく論理削除（ステータスを非アクティブに）
        @inventory.archived!

        # 成功時は204 No Content + 空ボディを返却
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
        # findメソッドはレコードが見つからない場合にActiveRecord::RecordNotFoundを発生させ、
        # ErrorHandlersが404ハンドリングしてくれる
        @inventory = Inventory.find(params[:id]).decorate
      end

      def inventory_params
        params.require(:inventory).permit(:name, :quantity, :price, :status, :category, :unit, :minimum_stock, :lock_version)
      end
    end
  end
end
