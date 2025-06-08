# frozen_string_literal: true

module ErrorHandlers
  extend ActiveSupport::Concern

  included do
    # 基本的なActiveRecordエラー
    rescue_from ActiveRecord::RecordNotFound,       with: ->(e) { render_error 404, e }
    rescue_from ActiveRecord::RecordInvalid,        with: ->(e) { render_error 422, e }
    rescue_from ActiveRecord::RecordNotDestroyed,   with: ->(e) { render_error 422, e }

    # パラメータ関連エラー
    rescue_from ActionController::ParameterMissing, with: ->(e) { render_error 400, e }
    rescue_from ActionController::BadRequest,       with: ->(e) { render_error 400, e }

    # 認可関連エラー (Pundit導入時に有効化)
    # rescue_from Pundit::NotAuthorizedError,       with: -> (e) { render_error 403, e }

    # レートリミット (将来の拡張)
    # rescue_from Rack::Attack::Throttle,           with: ->(e) { render_error 429, e }

    # 独自例外クラス
    rescue_from CustomError::BaseError, with: ->(e) { render_custom_error e }

    # TODO: 注意事項 - エラーハンドリングとDeviseの競合
    # 1. routes.rbでは、Deviseルートをエラーハンドリングルートより先に定義する
    # 2. ワイルドカードルート（*path）は常に最後に定義する
    # 3. 新規機能追加時は、既存ルートとの競合可能性に注意する
    # 4. ルーティング順序を変更した場合は、認証機能とエラーページの動作を必ず確認する
    # 詳細は doc/error_handling_guide.md の「ルーティング順序の問題」を参照

    # TODO: Phase 3実装予定（高優先度）
    # 1. Sentry/DataDog連携によるエラー追跡・アラート機能
    #    - 本番環境での500エラー自動通知
    #    - エラー頻度・パターン分析ダッシュボード
    #    - スタックトレース詳細とコンテキスト情報記録
    #    - パフォーマンス劣化検知機能
    #
    # 2. Pundit認可システム連携
    #    - 403 Forbiddenエラーハンドリング完全実装
    #    - ロールベースアクセス制御
    #    - 管理者・一般ユーザー権限分離
    #    - 操作履歴とセキュリティ監査
    #
    # 3. レート制限機能（Rack::Attack）
    #    - API呼び出し頻度制限
    #    - ブルートフォース攻撃対策
    #    - 地域別アクセス制限
    #    - 429 Too Many Requestsエラー統合

    # TODO: Phase 4実装予定（中優先度）
    # 1. 国際化完全対応
    #    - 全エラーメッセージの多言語化（英語・中国語・韓国語）
    #    - ロケール自動検出機能
    #    - タイムゾーン対応エラーログ
    #    - 地域別エラーページカスタマイズ
    #
    # 2. キャッシュ戦略最適化
    #    - エラーページの適切なキャッシュ設定
    #    - CDN連携によるエラーページ配信高速化
    #    - Redis活用エラー情報一時保存
    #    - エラー発生パターンのメモ化
    #
    # 3. 詳細ログ・監査機能
    #    - ユーザー操作フロー追跡
    #    - エラー前後のコンテキスト情報記録
    #    - IP・UserAgent詳細分析
    #    - 不正アクセス検知・自動ブロック機能
  end

  private

  # エラーの記録とレスポンス形式に応じた返却を行う
  # @param status [Integer] HTTPステータスコード
  # @param exception [Exception] 発生した例外オブジェクト
  def render_error(status, exception)
    # エラーログに記録（request_idを含む）
    log_error(status, exception)

    # リクエスト形式に応じたレスポンス処理
    respond_to do |format|
      # JSON API向けレスポンス
      format.json { render json: json_error(status, exception), status: status }

      # HTML（ブラウザ）向けレスポンス
      format.html do
        # 422の場合はフォーム再表示するため、直接エラーページにリダイレクトしない
        if status == 422
          flash.now[:alert] = exception.message
          # コントローラに応じた処理を行う必要があるため、各コントローラで対応
        else
          # テスト環境では直接ステータスコードを返す（API的な動作をテスト可能にするため）
          # 本番・開発環境ではエラーページにリダイレクト
          if Rails.env.test?
            render plain: exception.message, status: status
          else
            redirect_to error_path(code: status)
          end
        end
      end

      # Turbo Stream向けレスポンス
      format.turbo_stream do
        render partial: "shared/error", status: status, locals: {
          message: exception.message,
          details: extract_error_details(exception)
        }
      end
    end
  end

  # カスタムエラーの処理（ApiResponse統合版）
  # @param exception [CustomError::BaseError] 発生したカスタムエラー
  def render_custom_error(exception)
    status = exception.status
    log_error(status, exception)

    respond_to do |format|
      # JSON API向けレスポンス（ApiResponse統合）
      format.json do
        api_response = ApiResponse.from_exception(
          exception,
          {
            request_id: request.request_id,
            user_id: defined?(current_admin) ? current_admin&.id : nil,
            path: request.fullpath,
            timestamp: Time.current.iso8601
          }
        )
        render json: api_response.to_h, status: api_response.status_code, headers: api_response.headers
      end

      # HTML（ブラウザ）向けレスポンス
      format.html do
        if status == 422
          flash.now[:alert] = exception.message
          # 422の場合はコントローラで個別に対応
        else
          # テスト環境では直接ステータスコードを返す（API的な動作をテスト可能にするため）
          # 本番・開発環境ではエラーページにリダイレクト
          if Rails.env.test?
            render plain: exception.message, status: status
          else
            redirect_to error_path(code: status)
          end
        end
      end

      # Turbo Stream向けレスポンス
      format.turbo_stream do
        render partial: "shared/error", status: status, locals: {
          message: exception.message,
          details: exception.details
        }
      end
    end
  end

  # エラーログへの記録
  # @param status [Integer] HTTPステータスコード
  # @param exception [Exception] 発生した例外
  def log_error(status, exception)
    severity = status >= 500 ? :error : :info

    log_data = {
      status: status,
      error: exception.class.name,
      message: exception.message,
      request_id: request.request_id,
      user_id: defined?(current_user) ? current_user&.id : nil,
      path: request.fullpath,
      params: filtered_parameters
    }

    # スタックトレースは500エラーの場合のみ記録
    log_data[:backtrace] = exception.backtrace[0..5] if status >= 500

    Rails.logger.send(severity) { log_data.to_json }

    # TODO: Phase 3実装予定 - 外部監視サービス連携
    # 1. Sentry連携（エラー追跡・アラート）
    #    if status >= 500
    #      Sentry.capture_exception(exception, extra: {
    #        request_id: request.request_id,
    #        user_id: current_user&.id,
    #        path: request.fullpath,
    #        params: filtered_parameters
    #      })
    #    end
    #
    # 2. DataDog APM連携（パフォーマンス監視）
    #    Datadog::Tracing.trace("error_handling") do |span|
    #      span.set_tag("http.status_code", status)
    #      span.set_tag("error.type", exception.class.name)
    #      span.set_tag("user.id", current_user&.id) if current_user
    #    end
    #
    # 3. Slack通知連携（重要エラーの即座な通知）
    #    if status >= 500 && Rails.env.production?
    #      ErrorNotificationJob.perform_later(exception, log_data)
    #    end
  end

  # JSON APIエラーレスポンスの生成（ApiResponse統合版）
  # @param status [Integer] HTTPステータスコード
  # @param exception [Exception] 発生した例外
  # @return [Hash] JSONレスポンス用ハッシュ
  def json_error(status, exception)
    # ApiResponseを使用して統一的なエラーレスポンスを生成
    api_response = ApiResponse.from_exception(
      exception,
      {
        request_id: request.request_id,
        user_id: defined?(current_admin) ? current_admin&.id : nil,
        path: request.fullpath,
        timestamp: Time.current.iso8601
      }
    )

    api_response.to_h
  end

  # ステータスコードとエラー種別からエラーコードを決定
  # @param status [Integer] HTTPステータスコード
  # @param exception [Exception] 発生した例外
  # @return [String] エラーコード文字列
  def error_code_for_status(status, exception)
    case
    when exception.is_a?(ActiveRecord::RecordNotFound)
      "resource_not_found"
    when exception.is_a?(ActiveRecord::RecordInvalid)
      "validation_error"
    when exception.is_a?(ActionController::ParameterMissing)
      "parameter_missing"
    # when exception.is_a?(Pundit::NotAuthorizedError)
    #   "forbidden"
    else
      # 標準的なHTTPステータスをスネークケースに
      Rack::Utils::HTTP_STATUS_CODES[status].downcase.gsub(/\s|-/, "_")
    end
  end

  # 例外からエラー詳細を抽出
  # @param exception [Exception] 発生した例外
  # @return [Array, nil] エラー詳細の配列またはnil
  def extract_error_details(exception)
    case exception
    when ActiveRecord::RecordInvalid
      # ActiveRecordバリデーションエラーの詳細を取得
      exception.record.errors.full_messages
    when ActiveModel::ValidationError
      # ActiveModelバリデーションエラーの詳細を取得
      exception.model.errors.full_messages
    else
      nil
    end
  end

  # パラメータのフィルタリング（ログ記録用）
  # @return [Hash] フィルタリングされたパラメータ
  def filtered_parameters
    request.filtered_parameters.except(*%w[controller action format])
  end
end
