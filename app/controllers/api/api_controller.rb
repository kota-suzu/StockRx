# frozen_string_literal: true

module Api
  # API共通のベースコントローラ
  # すべてのAPIコントローラはこのクラスを継承する
  class ApiController < ApplicationController
    # CSRFチェックをスキップ（APIはトークン認証を使用するため）
    # 注意: 将来的には認証導入時にこのスキップを削除し、
    #      トークンベースのCSRF保護に置き換える
    skip_before_action :verify_authenticity_token

    # レスポンスのデフォルトJSONフォーマットを設定
    before_action :set_default_format

    # レスポンスフォーマット強制
    before_action :ensure_json_request

    # API用リクエスト情報をCurrentに設定
    before_action :set_api_request_info

    private

    # リクエストがJSONであることを確認
    def ensure_json_request
      return if request.format.json?

      # JSON以外のリクエストは拒否
      render json: {
        code: "invalid_format",
        message: "JSONリクエストのみ対応しています"
      }, status: :not_acceptable
    end

    # デフォルトレスポンス形式をJSONに設定
    def set_default_format
      request.format = :json unless params[:format]
    end

    # APIリクエスト情報をCurrentに設定
    def set_api_request_info
      Current.api_version = request.headers["X-API-Version"] || "v1"
      Current.api_client = request.headers["X-API-Client"] || "unknown"

      # 将来的に認証情報を追加
      # Current.user = ...
    end

    # ==============================================================
    # 認証・認可関連のメソッド
    # ==============================================================
    # 将来的な実装用にスケルトンを定義

    # 認証されたユーザーを要求
    # def authenticate_user!
    #   unless current_user
    #     render json: {
    #       code: "unauthorized",
    #       message: "認証が必要です"
    #     }, status: :unauthorized
    #   end
    # end

    # レート制限チェック
    # def check_rate_limit!
    #   if rate_limited?
    #     raise CustomError::RateLimitExceeded.new(
    #       "短時間に多くのリクエストが行われました",
    #       ["しばらく待ってから再試行してください"]
    #     )
    #   end
    # end

    # private

    # def rate_limited?
    #   # Redisなどを使ったレート制限の実装
    #   false
    # end
  end
end
