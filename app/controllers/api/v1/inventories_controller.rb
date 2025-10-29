# frozen_string_literal: true

module Api
  module V1
    class InventoriesController < Api::ApiController
      # API認証（オプショナル）でレート制限を緊和
      before_action :authenticate_api_key
      # 管理者権限が必要なアクション
      before_action :ensure_admin_permissions!, only: [ :create, :update, :destroy ]
      protect_from_forgery with: :null_session
      before_action :set_inventory, only: %i[show update destroy]

      # GET /api/v1/inventories
      def index
        # SearchQueryBuilderを使用してSearchResult形式で結果を取得
        # パフォーマンス最適化: batchesのincludesは必要な場合のみ
        base_query = if params[:include_batches] == "true"
                      Inventory.includes(:batches)
        else
                      Inventory.all
        end

        search_builder = SearchQueryBuilder
          .build(base_query)
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

        begin
          @inventory.destroy!
        rescue ActiveRecord::DeleteRestrictionError => e
          # dependent: :restrict_with_errorによる制約違反
          response = ApiResponse.error(
            "在庫に関連するデータがあるため削除できません",
            [ "関連するログや店舗在庫を先に削除してください" ],
            422,
            { type: "delete_restriction", details: e.message }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        rescue ActiveRecord::RecordNotDestroyed => e
          # その他の削除制約エラー（外部キー制約など）
          response = ApiResponse.error(
            "在庫を削除できませんでした",
            e.record.errors.full_messages,
            422,
            { type: "delete_failed", details: e.message }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        end

        # 成功時は204 No Content + 空ボディを返却
        # 204 No Contentの場合は本当に空のボディを返す（HTTP標準準拠）
        head :no_content
      end

      # GET /api/v1/inventories/bulk
      def bulk
        # 大量データ取得用（最大1000件）
        per_page = [ params[:per_page].to_i, 1000 ].min
        per_page = 100 if per_page <= 0

        search_builder = SearchQueryBuilder
          .build(Inventory.includes(:batches))
          .filter_by_name(params[:name])
          .filter_by_status(params[:status])
          .order_by(params[:sort] || "updated_at", params[:direction] || "desc")

        search_result = search_builder.execute(
          page: params[:page] || 1,
          per_page: per_page
        )

        response = ApiResponse.paginated(
          search_result,
          "在庫データを一括取得しました（#{search_result.total_count}件中#{search_result.size}件）",
          {
            bulk_operation: true,
            max_per_page: 1000,
            search_conditions: search_result.conditions_summary
          }
        )

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # POST /api/v1/inventories/bulk_create
      def bulk_create
        inventories_params = params.require(:inventories)

        unless inventories_params.is_a?(Array)
          response = ApiResponse.error(
            "一括作成データはinventories配列で指定してください",
            [],
            400,
            { type: "invalid_bulk_data" }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        end

        if inventories_params.length > 100
          response = ApiResponse.error(
            "一度に作成できるのは100件までです",
            [],
            422,
            { type: "bulk_limit_exceeded", max_items: 100 }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        end

        results = { created: [], failed: [] }

        Inventory.transaction do
          inventories_params.each_with_index do |inventory_params, index|
            inventory = Inventory.new(permitted_params(inventory_params))

            if inventory.save
              results[:created] << { index: index, inventory: inventory.decorate }
            else
              results[:failed] << {
                index: index,
                data: inventory_params,
                errors: inventory.errors.full_messages
              }
            end
          end

          # ひとつでも失敗したらロールバック
          if results[:failed].any?
            raise ActiveRecord::Rollback
          end
        end

        if results[:failed].any?
          response = ApiResponse.error(
            "一括作成に失敗しました",
            results[:failed].map { |f| "インデックス#{f[:index]}: #{f[:errors].join(', ')}" },
            422,
            { type: "bulk_creation_failed", details: results[:failed] }
          )
        else
          response = ApiResponse.created(
            results[:created].map { |c| c[:inventory] },
            "#{results[:created].size}件の在庫が正常に作成されました"
          )
        end

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # PATCH /api/v1/inventories/bulk_update
      def bulk_update
        updates_params = params.require(:updates)

        unless updates_params.is_a?(Array)
          response = ApiResponse.error(
            "一括更新データはupdates配列で指定してください",
            [],
            400,
            { type: "invalid_bulk_data" }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        end

        if updates_params.length > 100
          response = ApiResponse.error(
            "一度に更新できるのは100件までです",
            [],
            422,
            { type: "bulk_limit_exceeded", max_items: 100 }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        end

        results = { updated: [], failed: [] }

        Inventory.transaction do
          updates_params.each_with_index do |update_params, index|
            inventory_id = update_params[:id]

            unless inventory_id
              results[:failed] << {
                index: index,
                data: update_params,
                errors: [ "IDが指定されていません" ]
              }
              next
            end

            begin
              inventory = Inventory.find(inventory_id)

              if inventory.update(permitted_params(update_params.except(:id)))
                results[:updated] << { index: index, inventory: inventory.reload.decorate }
              else
                results[:failed] << {
                  index: index,
                  data: update_params,
                  errors: inventory.errors.full_messages
                }
              end
            rescue ActiveRecord::RecordNotFound
              results[:failed] << {
                index: index,
                data: update_params,
                errors: [ "ID #{inventory_id}の在庫が見つかりません" ]
              }
            end
          end

          # ひとつでも失敗したらロールバック
          if results[:failed].any?
            raise ActiveRecord::Rollback
          end
        end

        if results[:failed].any?
          response = ApiResponse.error(
            "一括更新に失敗しました",
            results[:failed].map { |f| "インデックス#{f[:index]}: #{f[:errors].join(', ')}" },
            422,
            { type: "bulk_update_failed", details: results[:failed] }
          )
        else
          response = ApiResponse.success(
            results[:updated].map { |u| u[:inventory] },
            "#{results[:updated].size}件の在庫が正常に更新されました"
          )
        end

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # DELETE /api/v1/inventories/bulk_destroy
      def bulk_destroy
        ids = params.require(:ids)

        unless ids.is_a?(Array)
          response = ApiResponse.error(
            "一括削除のIDはids配列で指定してください",
            [],
            400,
            { type: "invalid_bulk_data" }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        end

        if ids.length > 50
          response = ApiResponse.error(
            "一度に削除できるのは50件までです",
            [],
            422,
            { type: "bulk_limit_exceeded", max_items: 50 }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
          return
        end

        results = { deleted: [], failed: [] }

        Inventory.transaction do
          ids.each_with_index do |id, index|
            begin
              inventory = Inventory.find(id)
              inventory.destroy!
              results[:deleted] << { index: index, id: id }
            rescue ActiveRecord::RecordNotFound
              results[:failed] << {
                index: index,
                id: id,
                errors: [ "ID #{id}の在庫が見つかりません" ]
              }
            rescue ActiveRecord::DeleteRestrictionError, ActiveRecord::RecordNotDestroyed => e
              results[:failed] << {
                index: index,
                id: id,
                errors: [ "削除制約により削除できません" ]
              }
            end
          end

          # ひとつでも失敗したらロールバック
          if results[:failed].any?
            raise ActiveRecord::Rollback
          end
        end

        if results[:failed].any?
          response = ApiResponse.error(
            "一括削除に失敗しました",
            results[:failed].map { |f| "ID #{f[:id]}: #{f[:errors].join(', ')}" },
            422,
            { type: "bulk_delete_failed", details: results[:failed] }
          )
          render json: response.to_h, status: response.status_code, headers: response.headers
        else
          # 204 No Content
          head :no_content
        end
      end

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

      # 管理者権限の確認
      def ensure_admin_permissions!
        unless api_admin_can?(:write) || api_store_user_can?(:write)
          render_authorization_error("在庫管理の権限がありません")
        end
      end

      def set_inventory
        # findメソッドはレコードが見つからない場合にActiveRecord::RecordNotFoundを発生させ、
        # ErrorHandlersが404ハンドリングしてくれる
        # パフォーマンス最適化: showアクションでのみbatchesをinclude
        @inventory = if action_name == "show" && params[:include_batches] != "false"
                      Inventory.includes(:batches).find(params[:id]).decorate
        else
                      Inventory.find(params[:id]).decorate
        end
      end

      def inventory_params
        params.require(:inventory).permit(:name, :quantity, :price, :status, :lock_version)
      end

      # バルク操作用のパラメーター許可
      def permitted_params(param_hash)
        ActionController::Parameters.new(param_hash).permit(:name, :quantity, :price, :status, :lock_version)
      end
    end
  end
end
