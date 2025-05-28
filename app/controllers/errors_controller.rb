class ErrorsController < ActionController::Base
  # ApplicationControllerを継承せずActionController::Baseを直接継承
  # これにより認証やCSRF保護などが適用されない

  # エラーハンドリングを追加
  include ErrorHandlers

  # レイアウトを指定（シンプルなエラーページ用レイアウト）
  layout "error"

  # エラーページの表示
  # @param code [String] エラーコード (404, 403, 500など)
  def show
    # リクエストのコードパラメータまたはパスから取得
    @code = params[:code] || extract_status_code_from_path

    # 対応するステータスコードに変換（数値保証）
    @status = @code.to_i

    # ステータスコードが0の場合（パスから取得を試みる）
    if @status == 0
      @status = extract_status_code_from_path.to_i
    end

    # サポートしていないステータスコードの場合は500に
    @status = 500 unless [ 400, 403, 404, 422, 429, 500 ].include?(@status)

    # メッセージの設定（i18n対応）
    @message = t("errors.status.#{@status}", default: nil) ||
              Rack::Utils::HTTP_STATUS_CODES[@status] ||
              "エラーが発生しました"

    # HTTPステータスコードを設定して明示的にレイアウトを指定
    respond_to do |format|
      format.html { render :show, status: @status, layout: "error" }
      format.json { render json: { error: @message, status: @status }, status: @status }
    end
  end

  private

  # パスからステータスコードを抽出
  # 例: /404 -> 404, /500 -> 500
  # @return [String] ステータスコード
  def extract_status_code_from_path
    # パスが /404 のような形式の場合、スラッシュを除去して数値部分を抽出
    path_code = request.path.gsub(/^\//, '')
    # 数値であることを確認
    path_code.match?(/^\d{3}$/) ? path_code : "500"
  end
end
