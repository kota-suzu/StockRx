class ErrorsController < ApplicationController
  # CSRFチェックをスキップ（エラーページは状態変更なし）
  skip_before_action :verify_authenticity_token

  # レイアウトを指定（シンプルなエラーページ用レイアウト）
  layout "error"

  # ============================================
  # TODO: エラーハンドリング改善計画（高優先度、1-2日）
  # ============================================
  # 1. HTTPステータスコード問題の解決
  #    - テスト環境でのステータスコード200問題を修正
  #    - render statusが正しく機能するよう調査・修正
  #    - ApplicationControllerのrescue_fromとの相互作用確認
  #
  # 2. ルーティング最適化
  #    - ワイルドカードルート順序の見直し
  #    - Rails内部ルート除外の改善
  #    - カスタムエラーページの優先順位調整
  #
  # 3. エラー監視・ログ収集強化
  #    - Sentry, Rollbar等の外部エラー監視サービス統合
  #    - 構造化ログによるエラー分析改善
  #    - アラート機能（重要エラーの即座通知）
  #
  # 4. ユーザー体験改善
  #    - エラーページデザインの向上
  #    - 多言語対応（i18n）
  #    - 検索機能・関連ページ提案の追加

  # エラーページの表示
  # @param code [String] エラーコード (404, 403, 500など)
  def show
    # リクエストのコードパラメータまたはパスから取得
    @code = params[:code] || extract_status_code_from_path

    # 対応するステータスコードに変換（数値保証）
    @status = @code&.to_i

    # サポートしていないステータスコードの場合は500に
    @status = 500 unless @status && @status > 0 && [ 400, 403, 404, 422, 429, 500 ].include?(@status)

    # メッセージの設定（i18n対応）
    @message = t("errors.status.#{@status}", default: nil) ||
              Rack::Utils::HTTP_STATUS_CODES[@status] ||
              "エラーが発生しました"

    # HTTPステータスコードを明示的に設定
    respond_to do |format|
      format.html do
        render "show", status: @status
      end
      format.json do
        render json: { error: @message, code: @status }, status: @status
      end
    end
  end

  private

  # パスからステータスコードを抽出
  # 例: /404 -> 404, /500 -> 500
  # @return [String] ステータスコード
  def extract_status_code_from_path
    # パスから最後の数字部分を抽出
    path_code = request.path.split("/").last
    # 数値として有効かチェック
    path_code if path_code.match?(/\A\d+\z/) && [ "400", "403", "404", "422", "429", "500" ].include?(path_code)
  end
end
