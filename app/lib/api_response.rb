# frozen_string_literal: true

# ApiResponse - API応答の統一化とエラーハンドリング改善
#
# 設計書に基づいた統一的なAPI応答オブジェクト
# セキュリティ、監査、エラーハンドリングを統合
ApiResponse = Struct.new(
  :success,      # Boolean
  :data,         # Any (主要データ)
  :message,      # String (ユーザー向けメッセージ)
  :errors,       # Array<String> (エラー詳細)
  :metadata,     # Hash (追加情報)
  :status_code,  # Integer (HTTPステータスコード)
  keyword_init: true
) do
  # ============================================
  # ファクトリーメソッド
  # ============================================

  def self.success(data = nil, message = nil, metadata = {})
    new(
      success: true,
      data: data,
      message: message || default_success_message(data),
      errors: [],
      metadata: base_metadata.merge(metadata),
      status_code: 200
    )
  end

  def self.created(data = nil, message = nil, metadata = {})
    new(
      success: true,
      data: data,
      message: message || "リソースが正常に作成されました",
      errors: [],
      metadata: base_metadata.merge(metadata),
      status_code: 201
    )
  end

  def self.no_content(message = "処理が正常に完了しました", metadata = {})
    new(
      success: true,
      data: nil,
      message: message,
      errors: [],
      metadata: base_metadata.merge(metadata),
      status_code: 204
    )
  end

  def self.error(message, errors = [], status_code = 422, metadata = {})
    new(
      success: false,
      data: nil,
      message: message,
      errors: normalize_errors(errors),
      metadata: base_metadata.merge(metadata),
      status_code: status_code
    )
  end

  def self.validation_error(errors, message = "入力データに問題があります")
    error(message, errors, 422, { type: "validation_error" })
  end

  def self.not_found(resource = "リソース", message = nil)
    message ||= "#{resource}が見つかりません"
    error(message, [], 404, { type: "not_found" })
  end

  def self.forbidden(message = "この操作を行う権限がありません")
    error(message, [], 403, { type: "forbidden" })
  end

  def self.conflict(message = "リソースの競合が発生しました")
    error(message, [], 409, { type: "conflict" })
  end

  def self.rate_limited(message = "リクエストが多すぎます", retry_after = 60)
    error(
      message,
      [],
      429,
      {
        type: "rate_limited",
        retry_after: retry_after
      }
    )
  end

  def self.internal_error(message = "内部エラーが発生しました")
    error(message, [], 500, { type: "internal_error" })
  end

  def self.from_exception(exception, metadata = {})
    case exception
    when ActiveRecord::RecordNotFound
      not_found("#{exception.model}", nil)
    when ActiveRecord::RecordInvalid
      validation_error(exception.record.errors.full_messages)
    when ActiveRecord::StaleObjectError
      conflict("他のユーザーがこのリソースを更新しました")
    when CustomError::ResourceConflict
      conflict(exception.message)
    when CustomError::RateLimitExceeded
      rate_limited(exception.message)
    when CustomError::Forbidden
      forbidden(exception.message)
    else
      internal_error(
        Rails.env.production? ? "内部エラーが発生しました" : exception.message
      )
    end.tap do |response|
      response.metadata.merge!(metadata)
    end
  end

  # ============================================
  # インスタンスメソッド
  # ============================================

  def successful?
    success == true
  end

  def failed?
    !successful?
  end

  def has_errors?
    errors.any?
  end

  def client_error?
    status_code >= 400 && status_code < 500
  end

  def server_error?
    status_code >= 500
  end

  # ============================================
  # 出力関連メソッド
  # ============================================

  def to_h
    {
      success: success,
      data: serialize_data,
      message: message,
      errors: errors,
      metadata: metadata
    }
  end

  def to_json(*args)
    to_h.to_json(*args)
  end

  def headers
    base_headers = {
      "Content-Type" => "application/json; charset=utf-8",
      "X-Response-Time" => metadata[:response_time]&.to_s,
      "X-Request-ID" => metadata[:request_id]
    }

    # セキュリティヘッダーの追加
    security_headers = {
      "X-Content-Type-Options" => "nosniff",
      "X-Frame-Options" => "DENY",
      "X-XSS-Protection" => "1; mode=block"
    }

    # レート制限の場合はRetry-Afterヘッダーを追加
    if status_code == 429 && metadata[:retry_after]
      security_headers["Retry-After"] = metadata[:retry_after].to_s
    end

    # HTTPS環境ではHSTSヘッダーを追加
    if Rails.application.config.force_ssl
      security_headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    end

    base_headers.merge(security_headers).compact
  end

  # ============================================
  # Rails統合メソッド
  # ============================================

  def render_options
    {
      json: to_h,
      status: status_code,
      headers: headers
    }
  end

  # ============================================
  # ページネーション統合メソッド
  # ============================================

  def self.paginated(search_result, message = nil, metadata = {})
    pagination_metadata = {
      pagination: search_result.pagination_info,
      search: search_result.search_metadata
    }

    merged_metadata = metadata.merge(pagination_metadata)

    success(
      search_result.sanitized_records,
      message || "データを#{search_result.total_count}件取得しました",
      merged_metadata
    )
  end

  # ============================================
  # デバッグ・ログ出力用メソッド
  # ============================================

  def log_summary
    summary = {
      success: success,
      status_code: status_code,
      message: message,
      error_count: errors.size,
      request_id: metadata[:request_id]
    }

    # 本番環境では機密データを除外
    unless Rails.env.production?
      summary[:data_type] = data.class.name
      summary[:metadata_keys] = metadata.keys
    end

    summary
  end

  private

  def serialize_data
    return nil if data.nil?

    case data
    when ActiveRecord::Base, Draper::Decorator
      data.serializable_hash
    when ActiveRecord::Relation, Array
      data.map(&:serializable_hash)
    when SearchResult
      data.to_api_hash
    when Hash
      data
    else
      data.respond_to?(:serializable_hash) ? data.serializable_hash : data
    end
  end

  def self.base_metadata
    {
      timestamp: Time.current.iso8601,
      request_id: Current.request_id || SecureRandom.uuid,
      version: "v1",
      admin_id: Current.admin&.id
    }
  end

  def self.normalize_errors(errors)
    case errors
    when String
      [ errors ]
    when Hash
      errors.flat_map { |key, messages| Array(messages).map { |msg| "#{key}: #{msg}" } }
    when ActiveModel::Errors
      errors.full_messages
    when Array
      errors.flatten.map(&:to_s)
    else
      [ errors.to_s ]
    end
  end

  def self.default_success_message(data)
    case data
    when ActiveRecord::Relation, Array
      count = data.respond_to?(:count) ? data.count : data.size
      "データを#{count}件取得しました"
    when ActiveRecord::Base
      "データを取得しました"
    when SearchResult
      "検索結果を#{data.total_count}件取得しました"
    else
      "処理が正常に完了しました"
    end
  end
end
