# frozen_string_literal: true

module Api
  module V1
    # APIキー管理コントローラー
    # CLAUDE.md準拠: 管理者用APIキー管理機能
    class ApiKeysController < Api::ApiController
      # 管理者認証必須
      before_action :authenticate_api_admin!
      before_action :set_api_key, only: [:show, :destroy, :revoke]

      # GET /api/v1/api_keys
      def index
        # 現在の認証されたユーザーのAPIキーのみ表示
        api_keys = current_admin.api_keys.includes(:admin, :store_user)
                              .order(created_at: :desc)
                              .page(params[:page])
                              .per(params[:per_page] || 20)

        response = ApiResponse.success(
          api_keys.map(&:as_json),
          "APIキー一覧を取得しました（#{api_keys.total_count}件）",
          {
            pagination: {
              current_page: api_keys.current_page,
              per_page: api_keys.limit_value,
              total_count: api_keys.total_count,
              total_pages: api_keys.total_pages
            }
          }
        )

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # GET /api/v1/api_keys/1
      def show
        response = ApiResponse.success(
          @api_key.as_json(include: {
            admin: { only: [:id, :email, :role] },
            store_user: { only: [:id, :email, :name] }
          }),
          "APIキー情報を取得しました"
        )

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # POST /api/v1/api_keys
      def create
        @api_key = current_admin.api_keys.build(api_key_params)

        if @api_key.save
          # 作成直後のみ、生のAPIキーを含めて返す
          response_data = @api_key.as_json.merge({
            "key" => @api_key.key,
            "warning" => "このAPIキーは今回のみ表示されます。安全な場所に保存してください。"
          })

          response = ApiResponse.created(
            response_data,
            "APIキーが正常に作成されました"
          )

          render json: response.to_h, status: response.status_code, headers: response.headers
        else
          response = ApiResponse.validation_error(
            @api_key.errors.full_messages,
            "APIキーの作成に失敗しました"
          )

          render json: response.to_h, status: response.status_code, headers: response.headers
        end
      end

      # DELETE /api/v1/api_keys/1
      def destroy
        begin
          @api_key.destroy!
          head :no_content
        rescue ActiveRecord::RecordNotDestroyed => e
          response = ApiResponse.error(
            "APIキーの削除に失敗しました",
            e.record.errors.full_messages,
            422,
            { type: "delete_failed", details: e.message }
          )

          render json: response.to_h, status: response.status_code, headers: response.headers
        end
      end

      # PATCH /api/v1/api_keys/1/revoke
      def revoke
        begin
          @api_key.revoke!(reason: params[:reason] || "管理者による手動失効")

          response = ApiResponse.success(
            @api_key.as_json,
            "APIキーが正常に失効されました"
          )

          render json: response.to_h, status: response.status_code, headers: response.headers
        rescue ActiveRecord::RecordInvalid => e
          response = ApiResponse.validation_error(
            e.record.errors.full_messages,
            "APIキーの失効に失敗しました"
          )

          render json: response.to_h, status: response.status_code, headers: response.headers
        end
      end

      private

      def set_api_key
        @api_key = current_admin.api_keys.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        response = ApiResponse.not_found("APIキー")
        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      def api_key_params
        params.require(:api_key).permit(:name, :description, :expires_at)
      end
    end
  end
end