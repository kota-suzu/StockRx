# frozen_string_literal: true

module Api
  module V1
    class InventoriesController < Api::ApiController
      before_action :authenticate_admin!
      protect_from_forgery with: :null_session
      before_action :set_inventory, only: %i[show update destroy]

      # GET /api/v1/inventories
      def index
        # SearchQueryBuilderを使用してSearchResult形式で結果を取得
        search_builder = SearchQueryBuilder
          .build(Inventory.includes(:batches))
          .filter_by_name(params[:name])
          .filter_by_status(params[:status])
          .filter_by_price_range(params[:min_price], params[:max_price])
          .filter_by_stock_status(params[:stock_filter])
          .order_by(params[:sort] || "updated_at", params[:direction] || "desc")

        search_result = search_builder.execute(
          page: params[:page] || 1,
          per_page: params[:per_page] || 20
        )

        # ApiResponse形式で統一レスポンス
        response = ApiResponse.paginated(
          search_result,
          "在庫データを検索しました",
          {
            search_conditions: search_result.conditions_summary,
            execution_time: search_result.execution_time
          }
        )

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # GET /api/v1/inventories/1
      def show
        # すでにset_inventoryで@inventoryが設定されている
        # エラーハンドリングはset_inventoryとErrorHandlersによって処理される
        response = ApiResponse.success(@inventory, "在庫情報を取得しました")
        render json: response.to_h, status: response.status_code, headers: response.headers
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

        # TODO: 横展開確認 - 作成後のオブジェクトをデコレート（一貫性確保）
        @inventory = @inventory.decorate

        # 成功時は201 Created + リソースの内容を返却
        response = ApiResponse.created(@inventory, "在庫が正常に作成されました")
        render json: response.to_h, status: response.status_code, headers: response.headers
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
        response = ApiResponse.success(@inventory.reload, "在庫情報が正常に更新されました")
        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # DELETE /api/v1/inventories/1
      def destroy
        # すでにset_inventoryで@inventoryが設定されている

        # TODO: 本番環境では論理削除を推奨（データ保全・監査対応）
        # 現在はAPIの一貫性を保つため物理削除を実装
        # 関連データ（batches, inventory_logs等）はdependent: :destroyで自動削除される

        # 削除前のデータ保全チェック（必要に応じて）
        # if @inventory.has_important_data?
        #   raise CustomError::BusinessLogicError, "重要なデータがあるため削除できません"
        # end

        @inventory.destroy!

        # 成功時は204 No Content + 空ボディを返却
        response = ApiResponse.no_content("在庫が正常に削除されました")
        render json: response.to_h, status: response.status_code, headers: response.headers
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
      # TODO: 残タスク実装計画（CLAUDE.md準拠）
      # ============================================

      # 🔴 緊急 - Phase 1（推定1-2日）
      # TODO: API削除処理の論理削除オプション実装
      # - 論理削除/物理削除の設定可能化
      # - 削除前の依存データチェック機能
      # - カスケード削除の安全性向上
      # - 削除履歴の監査ログ記録

      # TODO: APIエラーレスポンス形式の完全統一
      # - 422バリデーションエラーの詳細化
      # - 409競合エラーのハンドリング改善
      # - 429レート制限エラーの適切な実装
      # - エラーコード体系の標準化

      # 🟡 重要 - Phase 2（推定2-3日）
      # TODO: API認証・認可機能の強化
      # - JWT認証の実装
      # - スコープベースのアクセス制御
      # - APIキー管理機能
      # - レート制限の細かい制御

      # TODO: APIパフォーマンス最適化
      # - ページネーション機能の実装
      # - フィールド選択機能（GraphQL風）
      # - キャッシュ戦略の導入
      # - N+1クエリ問題の完全解決

      # 🟢 推奨 - Phase 3（推定1週間）
      # TODO: 高度なAPI機能
      # - バルク操作API（一括作成・更新・削除）
      # - 条件付きリクエスト（ETag、Last-Modified）
      # - WebSocket APIでのリアルタイム更新
      # - OpenAPI/Swagger仕様書の自動生成

      # TODO: 監視・運用機能
      # - APIメトリクス収集機能
      # - ヘルスチェックエンドポイント
      # - デバッグ用トレース情報の出力
      # - パフォーマンス監視ダッシュボード

      # 🔵 長期 - Phase 4（推定2-3週間）
      # TODO: 外部システム連携API
      # - 在庫同期API（外部システムとの双方向同期）
      # - バーコードスキャン連携API
      # - 発注システムAPI（自動発注処理）
      # - 会計システム連携API

      # TODO: AI・機械学習連携
      # - 需要予測API
      # - 在庫最適化推奨API
      # - 異常検知アラートAPI
      # - レポート自動生成API

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
        params.require(:inventory).permit(:name, :quantity, :price, :status, :lock_version)
      end
    end
  end
end
