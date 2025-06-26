# frozen_string_literal: true

# API Rate Limiting Concern
# CLAUDE.md準拠: コントローラーでのレート制限適用
module ApiRateLimiting
  extend ActiveSupport::Concern

  included do
    before_action :check_rate_limit!, if: :apply_rate_limiting?
  end

  private

  # レート制限チェック
  def check_rate_limit!
    limiter = api_rate_limiter
    result = limiter.check_limit

    # レート制限ヘッダーを設定
    set_rate_limit_headers(limiter, result)

    unless result[:allowed]
      # レート制限エラーを発生
      raise_rate_limit_error(result)
    end

    # リクエストを記録
    limiter.track_request
  end

  # APIレート制限オブジェクトを取得
  def api_rate_limiter
    @api_rate_limiter ||= ApiRateLimiter.new(
      identifier: rate_limit_identifier,
      user_type: rate_limit_user_type
    )
  end

  # レート制限識別子を生成
  def rate_limit_identifier
    # 優先順位: APIキー > 認証ユーザーID > IPアドレス
    if request.headers["X-API-Key"].present?
      "api_key:#{request.headers['X-API-Key']}"
    elsif current_admin.present?
      "admin:#{current_admin.id}"
    elsif current_store_user.present?
      "store_user:#{current_store_user.id}"
    else
      "ip:#{request.remote_ip}"
    end
  end

  # ユーザータイプを判定
  def rate_limit_user_type
    if current_admin.present? || current_store_user.present?
      :authenticated
    else
      :anonymous
    end
  end

  # レート制限ヘッダーを設定
  def set_rate_limit_headers(limiter, result)
    limiter.headers_for_response(result).each do |header, value|
      response.headers[header] = value
    end
  end

  # レート制限エラーを発生
  def raise_rate_limit_error(result)
    # CustomError::RateLimitExceededを使用
    error = CustomError::RateLimitExceeded.new(
      result[:message],
      ["再試行まで#{result[:retry_after]}秒お待ちください"]
    )
    
    # ApiResponseを使用してエラーレスポンスを生成
    api_response = ApiResponse.rate_limited(
      result[:message],
      result[:retry_after]
    )
    
    render json: api_response.to_h, 
           status: api_response.status_code, 
           headers: api_response.headers
  end


  # レート制限をスキップ（特定のアクション用）
  def skip_rate_limit!
    @skip_rate_limit = true
  end

  # オーバーライド用フック
  def apply_rate_limiting?
    # デフォルトの実装を提供
    base_apply_rate_limiting? && !@skip_rate_limit
  end
  
  # ベースの適用ロジック
  def base_apply_rate_limiting?
    # 開発環境ではデフォルトで無効化（環境変数で有効化可能）
    return false if Rails.env.development? && !ENV["ENABLE_API_RATE_LIMIT"]
    
    # テスト環境では無効化
    return false if Rails.env.test?
    
    # APIコントローラーでのみ有効化
    is_a?(Api::ApiController) || self.class.ancestors.include?(Api::ApiController)
  end
end