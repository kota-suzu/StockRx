# frozen_string_literal: true

# CSV Export Audit Job
# ========================================
# 責務: CSV出力の監査ログを非同期で記録
# 目的: パフォーマンス向上とユーザー体験の改善
# ========================================
class CsvExportAuditJob < ApplicationJob
  include SecureLogging

  queue_as :critical

  # 最大リトライ回数: 3回
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # 処理不可能エラー時の処理
  discard_on ActiveRecord::RecordNotFound

  def perform(user_id:, store_id:, record_count:, performance_metrics:, request_metadata:)
    # 🛡️ セキュリティ対策: 入力値の検証
    validate_input_parameters(user_id, store_id, record_count)

    # パフォーマンス監視開始
    start_time = Time.current

    # ユーザーと店舗の取得
    user = find_user(user_id)
    store = find_store(store_id) if store_id

    # 監査ログの作成
    create_audit_log_record(
      user: user,
      store: store,
      record_count: record_count,
      performance_metrics: performance_metrics,
      request_metadata: request_metadata
    )

    # 処理時間の記録
    processing_time = Time.current - start_time
    log_job_completion(user_id, store_id, record_count, processing_time)

  rescue StandardError => e
    # エラーログの記録（機密情報フィルタリング適用）
    log_job_error(e, user_id, store_id, record_count)
    raise # re-raise for retry mechanism
  end

  private

  # 入力パラメータの検証
  def validate_input_parameters(user_id, store_id, record_count)
    raise ArgumentError, "user_id is required" if user_id.blank?
    raise ArgumentError, "record_count must be non-negative" if record_count.negative?
    raise ArgumentError, "store_id must be positive" if store_id && store_id <= 0
  end

  # ユーザーの安全な取得
  def find_user(user_id)
    Admin.find(user_id)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error("User not found for CSV export audit: #{user_id}")
    raise
  end

  # 店舗の安全な取得
  def find_store(store_id)
    Store.find(store_id)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("Store not found for CSV export audit: #{store_id}")
    nil # 店舗が見つからない場合はnilを返す（処理は継続）
  end

  # 監査ログレコードの作成
  def create_audit_log_record(user:, store:, record_count:, performance_metrics:, request_metadata:)
    # 🛡️ セキュリティ対策: 機密情報のフィルタリング
    sanitized_metrics = sanitize_performance_metrics(performance_metrics)
    sanitized_metadata = sanitize_request_metadata(request_metadata)

    AuditLog.create!(
      user: user,
      action: "csv_export",
      details: {
        store_id: store&.id,
        store_name: store&.name,
        record_count: record_count,
        export_type: "inventory_list",
        performance_metrics: sanitized_metrics,
        job_metadata: {
          job_id: job_id,
          queue_name: queue_name,
          created_at: Time.current.iso8601
        }
      },
      ip_address: sanitized_metadata[:ip_address],
      user_agent: sanitized_metadata[:user_agent]
    )
  end

  # パフォーマンスメトリクスのサニタイズ
  def sanitize_performance_metrics(metrics)
    return {} unless metrics.is_a?(Hash)

    {
      memory_usage: sanitize_numeric_value(metrics[:memory_usage]),
      processing_time: sanitize_numeric_value(metrics[:processing_time]),
      batch_size: sanitize_numeric_value(metrics[:batch_size])
    }
  end

  # リクエストメタデータのサニタイズ
  def sanitize_request_metadata(metadata)
    return {} unless metadata.is_a?(Hash)

    {
      ip_address: sanitize_ip_address(metadata[:ip_address]),
      user_agent: sanitize_user_agent(metadata[:user_agent])
    }
  end

  # 数値の安全化
  def sanitize_numeric_value(value)
    return nil unless value.is_a?(Numeric)
    return nil if value.infinite? || value.nan?
    value.round(2)
  end

  # IPアドレスのサニタイズ
  def sanitize_ip_address(ip_address)
    return nil unless ip_address.is_a?(String)
    return nil unless ip_address.match?(/\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/)
    ip_address
  end

  # User-Agentのサニタイズ
  def sanitize_user_agent(user_agent)
    return nil unless user_agent.is_a?(String)
    # 長すぎるUser-Agentを制限
    user_agent.length > 500 ? user_agent[0..499] : user_agent
  end

  # ジョブ完了ログ
  def log_job_completion(user_id, store_id, record_count, processing_time)
    sanitized_log_data = {
      event: "csv_export_audit_completed",
      user_id: filter_sensitive_data(user_id.to_s),
      store_id: store_id,
      record_count: record_count,
      processing_time: processing_time.round(3),
      job_id: job_id,
      timestamp: Time.current.iso8601
    }

    Rails.logger.info(sanitized_log_data.to_json)
  end

  # ジョブエラーログ
  def log_job_error(error, user_id, store_id, record_count)
    # 🛡️ セキュリティ対策: エラーメッセージの機密情報フィルタリング
    sanitized_error_message = filter_sensitive_data(error.message)

    error_log_data = {
      event: "csv_export_audit_failed",
      user_id: filter_sensitive_data(user_id.to_s),
      store_id: store_id,
      record_count: record_count,
      error_class: error.class.name,
      error_message: sanitized_error_message,
      job_id: job_id,
      timestamp: Time.current.iso8601
    }

    Rails.logger.error(error_log_data.to_json)
  end
end
