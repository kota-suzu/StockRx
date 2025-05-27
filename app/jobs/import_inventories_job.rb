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

  private

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
      raise SecurityError, "File too large: #{file_size.to_s(:human_size)} (max: #{MAX_FILE_SIZE.to_s(:human_size)})"
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
  # Redis接続管理
  # ============================================
  def get_redis_connection
    # テスト環境では Redis のモック接続またはnilを返す
    if Rails.env.test?
      # テスト環境ではRedisが設定されていない場合があるため、nilを許容
      return nil unless defined?(Redis)

      begin
        # Redis接続テスト
        redis = Redis.current
        redis.ping  # 接続確認
        return redis
      rescue => e
        Rails.logger.warn "Redis not available in test environment: #{e.message}"
        return nil
      end
    end

    # 本番環境・開発環境
    begin
      if defined?(Sidekiq) && Sidekiq.redis_pool
        Sidekiq.redis { |conn| return conn }
      else
        # フォールバック: Redisが直接利用可能な場合
        Redis.current
      end
    rescue => e
      Rails.logger.warn "Redis connection failed, falling back to in-memory tracking: #{e.message}"
      nil
    end
  end

  # ============================================
  # 進捗追跡機能
  # ============================================
  def initialize_progress_tracking(redis, status_key, file_path, admin_id)
    return unless redis

    redis.hset(status_key,
      "status", "running",
      "started_at", Time.current.iso8601,
      "file_path", File.basename(file_path),  # セキュリティ：パスではなくファイル名のみ
      "progress", 0,
      "admin_id", admin_id,
      "job_class", self.class.name
    )
    redis.expire(status_key, 2.hours.to_i)  # 2時間後に自動削除

    Rails.logger.info "Progress tracking initialized: #{status_key}"

    # ActionCable経由でリアルタイム通知（初期化完了）
    broadcast_to_admin(admin_id, {
      type: "csv_import_initialized",
      job_id: status_key.split(":").last,
      status: "running",
      progress: 0,
      timestamp: Time.current.iso8601
    })
  end

  def update_progress(redis, status_key, progress, admin_id)
    return unless redis

    redis.hset(status_key, "progress", progress)

    # ActionCable経由でリアルタイム通知（AdminChannelを使用）
    broadcast_to_admin(admin_id, {
      type: "csv_import_progress",
      progress: progress,
      status_key: status_key,
      timestamp: Time.current.iso8601
    })
  end

  # ============================================
  # 成功時処理
  # ============================================
  def handle_success(result, admin_id, start_time, redis, status_key, duration)
    # Redis status update
    if redis
      redis.hset(status_key,
        "status", "completed",
        "completed_at", Time.current.iso8601,
        "duration", duration,
        "valid_count", result[:valid_count],
        "invalid_count", result[:invalid_records].size
      )
      redis.expire(status_key, 24.hours.to_i)  # 監査用に24時間保持
    end

    # 通知メッセージ作成
    admin = Admin.find_by(id: admin_id)
    if admin.present?
      message = I18n.t("inventories.import.completed", duration: duration) + "\n" +
                I18n.t("inventories.import.success", count: result[:valid_count]) + " " +
                I18n.t("inventories.import.invalid_records", count: result[:invalid_records].size)

      # ActionCable通知（AdminChannelを使用）
      broadcast_to_admin(admin_id, {
        type: "csv_import_complete",
        message: message,
        result: result,
        job_id: status_key.split(":").last,
        duration: duration,
        timestamp: Time.current.iso8601
      })

      # TODO: メール通知機能（大きなインポート処理向け）
      # AdminMailer.csv_import_complete(admin, result).deliver_later if result[:valid_count] > 1000
    end

    # 構造化ログ出力
    Rails.logger.info({
      event: "csv_import_completed",
      admin_id: admin_id,
      job_id: status_key.split(":").last,
      duration: duration,
      valid_count: result[:valid_count],
      invalid_count: result[:invalid_records].size,
      status_key: status_key
    }.to_json)
  end

  # ============================================
  # エラー時処理
  # ============================================
  def handle_error(exception, admin_id, file_path, redis, status_key)
    # リトライ回数の取得（Sidekiq環境とテスト環境で異なる）
    retry_count = if respond_to?(:executions)
                    executions
    elsif defined?(jid) && jid.present?
                    # Sidekiq環境でのリトライ回数取得を試行
                    job_data = Sidekiq::RetrySet.new.find_job(jid)
                    job_data ? job_data["retry_count"] || 0 : 0
    else
                    0  # テスト環境など
    end

    # Redis status update
    if redis
      redis.hset(status_key,
        "status", "failed",
        "failed_at", Time.current.iso8601,
        "error_message", exception.message,
        "error_class", exception.class.name,
        "retry_count", retry_count
      )
      redis.expire(status_key, 24.hours.to_i)  # エラー監査用に24時間保持
    end

    # 管理者への通知（AdminChannelを使用）
    admin = Admin.find_by(id: admin_id)
    if admin.present?
      broadcast_to_admin(admin_id, {
        type: "csv_import_error",
        message: I18n.t("inventories.import.error", message: exception.message),
        error_class: exception.class.name,
        retry_count: retry_count,
        max_retries: 3,
        job_id: status_key.split(":").last,
        timestamp: Time.current.iso8601
      })
    end

    # 構造化ログ出力
    Rails.logger.error({
      event: "csv_import_failed",
      admin_id: admin_id,
      job_id: status_key.split(":").last,
      error_class: exception.class.name,
      error_message: exception.message,
      retry_count: retry_count,
      file_path: File.basename(file_path),  # セキュリティ対応
      timestamp: Time.current.iso8601
    }.to_json)

    # TODO: 重要なエラーについて管理者に即座にメール通知
    # if retry_count >= 3
    #   AdminMailer.csv_import_failed(admin, exception, file_path).deliver_now
    # end
  end

  # ============================================
  # クリーンアップ処理
  # ============================================
  def cleanup_resources(file_path, redis, status_key)
    # 一時ファイルを削除（テスト環境では条件により削除）
    if File.exist?(file_path)
      # 本番環境では常に削除、テスト・開発環境では条件によって削除
      should_delete = Rails.env.production? ||
                     Rails.env.test? ||  # テスト環境でも削除をテスト
                     ENV["DELETE_TEMP_FILES"] == "true"

      if should_delete
        File.delete(file_path)
        Rails.logger.info "Temporary file deleted: #{File.basename(file_path)}"
      else
        Rails.logger.info "Temporary file preserved for debugging: #{File.basename(file_path)}"
      end
    end

    # TODO: 将来的な拡張クリーンアップ
    # - 古い進捗データの定期削除
    # - ファイルアップロード履歴の管理
    # - メモリ使用量の最適化
  rescue => e
    Rails.logger.warn "Cleanup failed: #{e.message}"
  end

  # ============================================
  # ActionCable通知の共通メソッド
  # ============================================
  def broadcast_to_admin(admin_id, data)
    begin
      # AdminChannelを使用してブロードキャスト
      AdminChannel.broadcast_to(
        Admin.find(admin_id),
        data
      )
    rescue => e
      Rails.logger.warn "AdminChannel broadcast failed: #{e.message}"

      # フォールバック：従来の方法を使用
      ActionCable.server.broadcast("admin_#{admin_id}", data)
    rescue => fallback_error
      Rails.logger.error "ActionCable broadcast completely failed: #{fallback_error.message}"
    end
  end

  # TODO: 将来的な機能拡張
  # ============================================
  # 1. 進捗通知の高度化
  #    - WebSocket経由のリアルタイム更新
  #    - プログレスバーの詳細表示
  #    - 処理速度の推定表示
  #
  # 2. エラーハンドリングの改善
  #    - エラー種別ごとの詳細対応
  #    - 部分的な成功データの保存
  #    - エラー行の特定と修正支援
  #
  # 3. パフォーマンス最適化
  #    - 並列処理による高速化
  #    - メモリ使用量の監視と最適化
  #    - バルクインサート・アップデートの実装
  #    - キューイング戦略の最適化
  #
  # 4. セキュリティ強化（優先度：高）
  #    - ファイル内容の詳細検証（マルウェアスキャン）
  #    - データサニタイゼーション強化
  #    - アップロード元IPの記録・制限
  #    - ファイルサイズ・形式の動的制限
  #
  # 5. 監査・トレーサビリティ強化
  #    - インポート履歴の詳細記録
  #    - データ変更の前後比較
  #    - ユーザー操作ログの詳細化
  #    - コンプライアンス対応（GDPR等）
  #
  # 6. 高可用性・災害復旧対応
  #    - インポート処理中断時の自動復旧
  #    - 重複処理の防止機構
  #    - バックアップ機能連携
  #    - クロスリージョン対応
  #
  # 7. ビジネスロジック拡張
  #    - 在庫自動補充ルールの適用
  #    - 価格変動アラートの生成
  #    - 需要予測データとの連携
  #    - 仕入先情報の自動マッピング
  #
  # 8. 運用効率化
  #    - スケジュール化されたインポート
  #    - APIベースのインポート機能
  #    - テンプレート機能（列マッピング保存）
  #    - バリデーションルールのカスタマイズ
  #
  # 9. 国際化・多言語対応
  #    - 多言語CSVヘッダー対応
  #    - 地域別データフォーマット対応
  #    - 通貨・数値形式の自動変換
  #    - タイムゾーンの考慮
  #
  # 10. 統合・連携機能
  #     - 外部システムとのAPI連携
  #     - ERPシステムとの同期
  #     - 在庫管理システムとの双方向連携
  #     - 分析ツールへのデータエクスポート
end
