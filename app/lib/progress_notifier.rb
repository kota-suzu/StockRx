# frozen_string_literal: true

# 進捗通知の共通モジュール
# 各種バックグラウンドジョブでの進捗通知機能を標準化
module ProgressNotifier
  extend ActiveSupport::Concern

  # ============================================
  # 進捗通知機能の初期化
  # ============================================
  def initialize_progress(admin_id, job_id, job_type, metadata = {})
    redis = get_redis_connection
    return nil unless redis

    status_key = "job_progress:#{job_id}"

    # Redis に進捗情報を保存
    redis.hset(status_key,
      "status", "running",
      "started_at", Time.current.iso8601,
      "admin_id", admin_id,
      "job_type", job_type,
      "job_class", self.class.name,
      "progress", 0,
      **metadata.stringify_keys
    )
    redis.expire(status_key, 2.hours.to_i)

    # ActionCable 経由で初期化通知
    broadcast_progress_update(admin_id, {
      type: "#{job_type}_initialized",
      job_id: job_id,
      job_type: job_type,
      status: "running",
      progress: 0,
      metadata: metadata,
      timestamp: Time.current.iso8601
    })

    Rails.logger.info "Progress tracking initialized: #{status_key} (#{job_type})"
    status_key
  end

  # ============================================
  # 進捗更新通知
  # ============================================
  def update_progress(status_key, admin_id, job_type, progress, message = nil)
    redis = get_redis_connection
    return unless redis && status_key

    # Redis の進捗を更新
    redis.hset(status_key, "progress", progress)
    redis.hset(status_key, "message", message) if message

    # ActionCable 経由で進捗通知
    broadcast_progress_update(admin_id, {
      type: "#{job_type}_progress",
      job_id: extract_job_id(status_key),
      job_type: job_type,
      progress: progress,
      message: message,
      timestamp: Time.current.iso8601
    })

    Rails.logger.debug "Progress updated: #{status_key} - #{progress}%"
  end

  # ============================================
  # 完了通知
  # ============================================
  def notify_completion(status_key, admin_id, job_type, result_data = {})
    redis = get_redis_connection
    job_id = extract_job_id(status_key)

    # Redis の状態を完了に更新
    if redis && status_key
      redis.hset(status_key,
        "status", "completed",
        "completed_at", Time.current.iso8601,
        "progress", 100,
        **result_data.stringify_keys
      )
      redis.expire(status_key, 24.hours.to_i)  # 監査用に24時間保持
    end

    # ActionCable 経由で完了通知
    broadcast_progress_update(admin_id, {
      type: "#{job_type}_complete",
      job_id: job_id,
      job_type: job_type,
      progress: 100,
      result: result_data,
      timestamp: Time.current.iso8601
    })

    Rails.logger.info "Job completed: #{status_key} (#{job_type})"
  end

  # ============================================
  # エラー通知
  # ============================================
  def notify_error(status_key, admin_id, job_type, exception, retry_count = 0)
    redis = get_redis_connection
    job_id = extract_job_id(status_key)

    # Redis の状態をエラーに更新
    if redis && status_key
      redis.hset(status_key,
        "status", "failed",
        "failed_at", Time.current.iso8601,
        "error_message", exception.message,
        "error_class", exception.class.name,
        "retry_count", retry_count
      )
      redis.expire(status_key, 24.hours.to_i)  # エラー監査用に24時間保持
    end

    # ActionCable 経由でエラー通知
    broadcast_progress_update(admin_id, {
      type: "#{job_type}_error",
      job_id: job_id,
      job_type: job_type,
      error_message: exception.message,
      error_class: exception.class.name,
      retry_count: retry_count,
      timestamp: Time.current.iso8601
    })

    Rails.logger.error "Job failed: #{status_key} (#{job_type}) - #{exception.message}"
  end

  # ============================================
  # 進捗状況の取得
  # ============================================
  def get_progress_status(job_id)
    redis = get_redis_connection
    return nil unless redis

    status_key = "job_progress:#{job_id}"
    job_data = redis.hgetall(status_key)

    return nil if job_data.empty?

    {
      job_id: job_id,
      status: job_data["status"],
      progress: job_data["progress"]&.to_i || 0,
      job_type: job_data["job_type"],
      started_at: job_data["started_at"],
      completed_at: job_data["completed_at"],
      failed_at: job_data["failed_at"],
      message: job_data["message"],
      error_message: job_data["error_message"],
      retry_count: job_data["retry_count"]&.to_i || 0
    }
  end

  private

  # ============================================
  # Redis接続管理
  # ============================================
  def get_redis_connection
    # ImportInventoriesJob と同じロジックを使用
    if Rails.env.test?
      return nil unless defined?(Redis)

      begin
        redis = Redis.current
        redis.ping
        return redis
      rescue => e
        Rails.logger.warn "Redis not available in test environment: #{e.message}"
        return nil
      end
    end

    begin
      if defined?(Sidekiq) && Sidekiq.redis_pool
        Sidekiq.redis { |conn| return conn }
      else
        Redis.current
      end
    rescue => e
      Rails.logger.warn "Redis connection failed: #{e.message}"
      nil
    end
  end

  # ============================================
  # ActionCable 通知
  # ============================================
  def broadcast_progress_update(admin_id, data)
    begin
      # AdminChannel を使用してブロードキャスト
      admin = Admin.find(admin_id)
      AdminChannel.broadcast_to(admin, data)
    rescue => e
      Rails.logger.warn "AdminChannel broadcast failed: #{e.message}"

      # フォールバック：従来の方法を使用
      begin
        ActionCable.server.broadcast("admin_#{admin_id}", data)
      rescue => fallback_error
        Rails.logger.error "ActionCable broadcast completely failed: #{fallback_error.message}"
      end
    end
  end

  # ============================================
  # ユーティリティメソッド
  # ============================================
  def extract_job_id(status_key)
    status_key&.split(":")&.last
  end

  # ============================================
  # 簡易版APIメソッド（既存ジョブとの互換性維持）
  # ============================================
  # これらのメソッドは既存のジョブで使用されている簡易版のインターフェースです
  # 新しいジョブでは、より詳細な制御が可能な上記のメソッドを使用することを推奨します

  # 簡易版：進捗開始通知
  # @param job_type [String] ジョブタイプ（例：'stock_alert', 'expiry_check'）
  # @param message [String] 開始メッセージ
  def notify_progress_start(job_type, message = nil)
    # 管理者IDを取得（Current.adminまたはデフォルト値を使用）
    admin_id = Current.admin&.id || 1
    job_id = SecureRandom.uuid

    # 初期化処理を実行
    initialize_progress(admin_id, job_id, job_type, { start_message: message })
    
    Rails.logger.info "Progress started: #{job_type} - #{message}"
  end

  # 簡易版：進捗完了通知
  # @param job_type [String] ジョブタイプ
  # @param message [String] 完了メッセージ
  # @param result_data [Hash] 結果データ
  def notify_progress_complete(job_type, message = nil, result_data = {})
    admin_id = Current.admin&.id || 1
    
    # 完了通知（status_keyが不明な場合は簡易版として処理）
    broadcast_progress_update(admin_id, {
      type: "#{job_type}_complete",
      job_type: job_type,
      message: message,
      result: result_data,
      progress: 100,
      timestamp: Time.current.iso8601
    })
    
    Rails.logger.info "Progress completed: #{job_type} - #{message}"
  end

  # 簡易版：エラー通知
  # @param job_type [String] ジョブタイプ
  # @param error_message [String] エラーメッセージ
  def notify_progress_error(job_type, error_message)
    admin_id = Current.admin&.id || 1
    
    # エラー通知
    broadcast_progress_update(admin_id, {
      type: "#{job_type}_error",
      job_type: job_type,
      error_message: error_message,
      timestamp: Time.current.iso8601
    })
    
    Rails.logger.error "Progress error: #{job_type} - #{error_message}"
  end
end

# ============================================
# TODO: 将来の拡張機能（優先度：中）
# ============================================
# 1. バッチ処理対応
#    - 複数ジョブの一括進捗管理
#    - 依存関係のあるジョブチェーン
#    - 並行処理の進捗統合
#
# 2. 通知のカスタマイズ
#    - 通知頻度の調整（毎回 vs 間隔指定）
#    - 通知内容のテンプレート化
#    - 管理者別の通知設定
#
# 3. 永続化・監査
#    - ジョブ履歴のデータベース保存
#    - パフォーマンス分析用データ収集
#    - SLA監視・アラート
#
# 4. 分散対応
#    - 複数サーバー間での進捗同期
#    - ロードバランサー対応
#    - 高可用性・フェイルオーバー
