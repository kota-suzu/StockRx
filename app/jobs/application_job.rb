class ApplicationJob < ActiveJob::Base
  # ============================================
  # Sidekiq Configuration for Background Jobs
  # ============================================
  # 要求仕様：3回リトライでエラーハンドリング強化

  # Sidekiq specific retry configuration
  # 指数バックオフによる自動復旧（1回目:即座、2回目:3秒、3回目:18秒）
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::ConnectionTimeoutError, wait: 10.seconds, attempts: 3

  # 回復不可能なエラーは即座に破棄
  discard_on ActiveJob::DeserializationError
  discard_on CSV::MalformedCSVError
  discard_on Errno::ENOENT  # ファイルが見つからない

  # TODO: 将来的な拡張エラーハンドリング
  # discard_on ActiveStorage::FileNotFoundError
  # retry_on Timeout::Error, wait: 30.seconds, attempts: 5  # Ruby 3.3対応：旧Net::TimeoutError

  # ============================================
  # Logging and Monitoring
  # ============================================
  # ジョブの可観測性向上のためのログ機能

  before_perform :log_job_start
  after_perform :log_job_success
  rescue_from StandardError, with: :log_job_error

  private

  def log_job_start
    @start_time = Time.current
    Rails.logger.info({
      event: "job_started",
      job_class: self.class.name,
      job_id: job_id,
      queue_name: queue_name,
      arguments: arguments.inspect,
      timestamp: @start_time.iso8601
    }.to_json)
  end

  def log_job_success
    duration = Time.current - @start_time if @start_time
    Rails.logger.info({
      event: "job_completed",
      job_class: self.class.name,
      job_id: job_id,
      duration: duration&.round(2),
      queue_name: queue_name,
      timestamp: Time.current.iso8601
    }.to_json)
  end

  def log_job_error(exception)
    duration = Time.current - @start_time if @start_time
    Rails.logger.error({
      event: "job_failed",
      job_class: self.class.name,
      job_id: job_id,
      duration: duration&.round(2),
      queue_name: queue_name,
      error_class: exception.class.name,
      error_message: exception.message,
      error_backtrace: exception.backtrace&.first(10),
      timestamp: Time.current.iso8601
    }.to_json)

    # エラーを再発生させてSidekiqのリトライ機能を働かせる
    raise exception
  end

  # TODO: 将来的な拡張機能
  # - メトリクス収集（Prometheus連携）
  # - アラート通知（Slack/Teams連携）
  # - パフォーマンス監視（NewRelic/Datadog連携）
  # - ジョブの依存関係管理
  # - バッチジョブのチェーン実行
end
