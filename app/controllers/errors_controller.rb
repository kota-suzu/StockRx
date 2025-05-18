class ErrorsController < ApplicationController
  # CSRFチェックをスキップ（エラーページは状態変更なし）
  skip_before_action :verify_authenticity_token

  # レイアウトを指定（シンプルなエラーページ用レイアウト）
  layout "error"

  # エラーページの表示
  # @param code [String] エラーコード (404, 403, 500など)
  def show
    # リクエストのコードパラメータまたはパスから取得
    @code = params[:code] || extract_status_code_from_path

    # 対応するステータスコードに変換（数値保証）
    @status = @code.to_i

    # サポートしていないステータスコードの場合は500に
    @status = 500 unless [ 400, 403, 404, 422, 429, 500 ].include?(@status)

    # メッセージの設定（i18n対応）
    @message = t("errors.status.#{@status}", default: nil) ||
              Rack::Utils::HTTP_STATUS_CODES[@status] ||
              "エラーが発生しました"

    # HTTPステータスコードを設定
    render status: @status
  end

  private

  # パスからステータスコードを抽出
  # 例: /404 -> 404, /500 -> 500
  # @return [String] ステータスコード
  def extract_status_code_from_path
    request.path.split("/").last.to_i.to_s
  end
end
