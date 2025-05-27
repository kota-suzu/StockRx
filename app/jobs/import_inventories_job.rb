# frozen_string_literal: true

# ============================================
# 在庫CSVインポートジョブ
# ============================================
# 機能:
#   - 大量の在庫データをCSVファイルから非同期でインポート
#   - Sidekiqによる3回自動リトライ機能
#   - リアルタイム進捗通知（ActionCable経由）
#   - 包括的なセキュリティ検証とエラーハンドリング
#
# 使用例:
#   ImportInventoriesJob.perform_later(file_path, admin.id)
#
class ImportInventoriesJob < ApplicationJob
  # ============================================
  # 設定定数
  # ============================================
  # ファイル制限
  MAX_FILE_SIZE = 100.megabytes
  ALLOWED_EXTENSIONS = %w[.csv].freeze
  REQUIRED_CSV_HEADERS = %w[name quantity price].freeze

  # バッチ処理設定
  IMPORT_BATCH_SIZE = 1000
  PROGRESS_REPORT_INTERVAL = 10 # 進捗報告の間隔（％）

  # Redis TTL設定
  PROGRESS_TTL = 1.hour
  COMPLETED_TTL = 24.hours

  # ============================================
  # Sidekiq設定
  # ============================================
  queue_as :imports
  sidekiq_options retry: 3, backtrace: true, queue: :imports

  # ============================================
  # コールバック
  # ============================================
  before_perform :validate_job_arguments

  # ============================================
  # メインメソッド
  # ============================================
  # CSVファイルから在庫データをインポート
  #
  # @param file_path [String] インポートするCSVファイルのパス
  # @param admin_id [Integer] 実行管理者のID
  # @param job_id [String, nil] ジョブ識別子（省略時は自動生成）
  # @return [Hash] インポート結果（valid_count, invalid_records）
  # @raise [StandardError] ファイル検証エラー、インポートエラー
  #
  def perform(file_path, admin_id, job_id = nil)
    @file_path = file_path
    @admin_id = admin_id
    @job_id = job_id || generate_job_id
    @start_time = Time.current

    with_error_handling do
      validate_and_import_csv
    end
  end

  private

  # ============================================
  # メイン処理フロー
  # ============================================
  def validate_and_import_csv
    # 1. セキュリティ検証
    validate_file_security

    # 2. 進捗追跡の初期化
    setup_progress_tracking

    # 3. CSVインポート実行
    result = execute_csv_import

    # 4. 成功通知
    notify_import_success(result)

    result
  end

  # ジョブ引数の検証
  def validate_job_arguments
    file_path = arguments[0]
    admin_id = arguments[1]

    raise ArgumentError, "File path is required" if file_path.blank?
    raise ArgumentError, "Admin ID is required" if admin_id.blank?
    raise ArgumentError, "Admin not found" unless Admin.exists?(admin_id)
  end

  # ジョブIDの生成
  def generate_job_id
    respond_to?(:jid) ? jid : SecureRandom.uuid
  end

  # ============================================
  # セキュリティ検証
  # ============================================
  def validate_file_security
    validate_file_existence
    validate_file_size
    validate_file_extension
    validate_csv_format
    validate_file_path_security

    log_security_validation_success
  end

  # ファイル存在確認
  def validate_file_existence
    raise SecurityError, "File not found: #{@file_path}" unless File.exist?(@file_path)
  end

  # ファイルサイズ検証
  def validate_file_size
    file_size = File.size(@file_path)
    if file_size > MAX_FILE_SIZE
      raise SecurityError, "File too large: #{ActiveSupport::NumberHelper.number_to_human_size(file_size)} (max: #{ActiveSupport::NumberHelper.number_to_human_size(MAX_FILE_SIZE)})"
    end
  end

  # ファイル拡張子検証
  def validate_file_extension
    extension = File.extname(@file_path).downcase
    unless ALLOWED_EXTENSIONS.include?(extension)
      raise SecurityError, "Invalid file type: #{extension}. Allowed types: #{ALLOWED_EXTENSIONS.join(', ')}"
    end
  end

  # CSV形式とヘッダー検証
  def validate_csv_format
    CSV.open(@file_path, "r", headers: true) do |csv|
      headers = csv.first&.headers&.map(&:downcase) || []
      missing_headers = REQUIRED_CSV_HEADERS - headers

      if missing_headers.any?
        raise CSV::MalformedCSVError, "Missing required headers: #{missing_headers.join(', ')}"
      end
    end
  rescue CSV::MalformedCSVError => e
    raise SecurityError, "Invalid CSV format: #{e.message}"
  end

  # パストラバーサル攻撃の防止
  def validate_file_path_security
    normalized_path = File.expand_path(@file_path)
    allowed_directories = [
      Rails.root.join("tmp").to_s,
      Rails.root.join("storage").to_s,
      "/tmp"
    ].map { |dir| File.expand_path(dir) }

    unless allowed_directories.any? { |dir| normalized_path.start_with?(dir) }
      raise SecurityError, "Unauthorized file location: #{@file_path}"
    end
  end

  def log_security_validation_success
    Rails.logger.info({
      event: "csv_import_security_validated",
      job_id: @job_id,
      file_name: File.basename(@file_path),
      file_size: File.size(@file_path)
    }.to_json)
  end

  # ============================================
  # エラーハンドリング
  # ============================================
  def with_error_handling
    yield
  rescue => e
    handle_import_error(e)
    raise e  # Sidekiqリトライのために再発生
  ensure
    cleanup_after_import
  end

  def handle_import_error(error)
    log_import_error(error)
    notify_import_error(error)
    update_error_status(error)
  end

  def log_import_error(error)
    Rails.logger.error({
      event: "csv_import_failed",
      job_id: @job_id,
      admin_id: @admin_id,
      error_class: error.class.name,
      error_message: error.message,
      error_backtrace: error.backtrace&.first(5),
      duration: calculate_duration
    }.to_json)
  end

  def cleanup_after_import
    cleanup_temp_file
    finalize_progress_tracking
  end

  def cleanup_temp_file
    return unless @file_path && File.exist?(@file_path)
    return if Rails.env.development? # 開発環境では削除しない

    File.delete(@file_path)
    Rails.logger.info "Temporary file cleaned up: #{File.basename(@file_path)}"
  rescue => e
    Rails.logger.warn "Failed to cleanup temp file: #{e.message}"
  end

  # ============================================
  # 進捗追跡
  # ============================================
  def setup_progress_tracking
    @redis = get_redis_connection
    @status_key = "csv_import:#{@job_id}"

    initialize_progress_in_redis if @redis
    broadcast_import_started
  end

  def initialize_progress_in_redis
    @redis.hset(@status_key,
      "status", "running",
      "started_at", @start_time.iso8601,
      "file_name", File.basename(@file_path),
      "admin_id", @admin_id,
      "job_class", self.class.name,
      "progress", 0
    )
    @redis.expire(@status_key, PROGRESS_TTL)
  end

  def update_import_progress(progress_percentage, message = nil)
    return unless @redis

    @redis.hset(@status_key, "progress", progress_percentage)
    @redis.hset(@status_key, "message", message) if message

    broadcast_progress_update(progress_percentage, message)
  end

  def finalize_progress_tracking
    return unless @redis && @status_key

    @redis.expire(@status_key, COMPLETED_TTL)
  end

  # ============================================
  # CSVインポート実行
  # ============================================
  def execute_csv_import
    log_import_start

    # バッチ処理でCSVをインポート
    result = Inventory.import_from_csv(@file_path, batch_size: IMPORT_BATCH_SIZE) do |progress|
      # 進捗更新（PROGRESS_REPORT_INTERVAL%ごとに通知）
      if progress % PROGRESS_REPORT_INTERVAL == 0
        update_import_progress(progress)
      end
    end

    log_import_complete(result)
    result
  end

  def log_import_start
    Rails.logger.info({
      event: "csv_import_started",
      job_id: @job_id,
      admin_id: @admin_id,
      file_name: File.basename(@file_path)
    }.to_json)
  end

  def log_import_complete(result)
    Rails.logger.info({
      event: "csv_import_completed",
      job_id: @job_id,
      duration: calculate_duration,
      valid_count: result[:valid_count],
      invalid_count: result[:invalid_records].size
    }.to_json)
  end

  # ============================================
  # 通知
  # ============================================
  def notify_import_success(result)
    update_success_status(result)
    broadcast_import_complete(result)
    send_completion_message(result)
  end

  def update_success_status(result)
    return unless @redis

    @redis.hset(@status_key,
      "status", "completed",
      "completed_at", Time.current.iso8601,
      "duration", calculate_duration,
      "valid_count", result[:valid_count],
      "invalid_count", result[:invalid_records].size
    )
  end

  def send_completion_message(result)
    admin = Admin.find_by(id: @admin_id)
    return unless admin

    message = build_completion_message(result)

    ActionCable.server.broadcast("admin_#{@admin_id}", {
      type: "csv_import_complete",
      message: message,
      result: {
        valid_count: result[:valid_count],
        invalid_count: result[:invalid_records].size,
        duration: calculate_duration
      }
    })
  end

  def notify_import_error(error)
    return unless @redis

    @redis.hset(@status_key,
      "status", "failed",
      "failed_at", Time.current.iso8601,
      "error_message", error.message,
      "error_class", error.class.name
    )

    broadcast_import_error(error)
  end

  def update_error_status(error)
    admin = Admin.find_by(id: @admin_id)
    return unless admin

    ActionCable.server.broadcast("admin_#{@admin_id}", {
      type: "csv_import_error",
      message: I18n.t("inventories.import.error", message: error.message),
      error: {
        class: error.class.name,
        message: error.message
      }
    })
  end

  # ============================================
  # ブロードキャスト
  # ============================================
  def broadcast_import_started
    broadcast_to_admin({
      type: "csv_import_initialized",
      job_id: @job_id,
      status: "running",
      progress: 0
    })
  end

  def broadcast_progress_update(progress, message = nil)
    data = {
      type: "csv_import_progress",
      job_id: @job_id,
      progress: progress,
      status_key: @status_key
    }
    data[:message] = message if message

    broadcast_to_admin(data)
  end

  def broadcast_import_complete(result)
    broadcast_to_admin({
      type: "csv_import_complete",
      job_id: @job_id,
      valid_count: result[:valid_count],
      invalid_count: result[:invalid_records].size,
      duration: calculate_duration
    })
  end

  def broadcast_import_error(error)
    broadcast_to_admin({
      type: "csv_import_error",
      job_id: @job_id,
      error_message: error.message,
      error_class: error.class.name
    })
  end

  def broadcast_to_admin(data)
    data[:timestamp] = Time.current.iso8601

    # AdminChannelを使用（可能な場合）
    admin = Admin.find_by(id: @admin_id)
    if admin
      begin
        AdminChannel.broadcast_to(admin, data)
      rescue
        # フォールバック
        ActionCable.server.broadcast("admin_#{@admin_id}", data)
      end
    end
  end

  # ============================================
  # ユーティリティメソッド
  # ============================================
  def get_redis_connection
    return get_test_redis if Rails.env.test?
    get_production_redis
  end

  def get_test_redis
    return nil unless defined?(Redis)

    Redis.current.tap(&:ping)
  rescue => e
    Rails.logger.warn "Redis not available in test: #{e.message}"
    nil
  end

  def get_production_redis
    if defined?(Sidekiq) && Sidekiq.redis_pool
      Sidekiq.redis { |conn| return conn }
    else
      Redis.current
    end
  rescue => e
    Rails.logger.warn "Redis connection failed: #{e.message}"
    nil
  end

  def calculate_duration
    return 0 unless @start_time
    ((Time.current - @start_time) / 1.second).round(2)
  end

  def build_completion_message(result)
    duration = calculate_duration
    valid_count = result[:valid_count]
    invalid_count = result[:invalid_records].size

    message = I18n.t("inventories.import.completed", duration: duration)
    message += "\n#{I18n.t('inventories.import.success', count: valid_count)}"
    message += " #{I18n.t('inventories.import.invalid_records', count: invalid_count)}" if invalid_count > 0

    message
  end

  # ============================================
  # TODO: 将来的な機能拡張（優先度：高）
  # ============================================
  # 1. インポートのプレビュー機能
  #    - 最初の10行を表示して確認
  #    - カラムマッピングのカスタマイズ
  #    - データ変換ルールの設定
  #
  # 2. インポート履歴管理
  #    - インポート履歴の永続化
  #    - 再実行機能
  #    - ロールバック機能
  #
  # 3. 高度なバリデーション
  #    - カスタムバリデーションルール
  #    - 重複チェックの最適化
  #    - 関連データの整合性チェック
  #
  # 4. パフォーマンス最適化
  #    - 並列処理対応
  #    - ストリーミング処理
  #    - メモリ使用量の最適化
  #
  # 5. 通知機能の拡張
  #    - メール通知（大規模インポート時）
  #    - Slack/Teams連携
  #    - 詳細レポートの生成
end
