# frozen_string_literal: true

# 管理者専用のActionCableチャンネル
# CSVインポート進捗や在庫アラートなどのリアルタイム通知を担当
class AdminChannel < ApplicationCable::Channel
  # ============================================
  # チャンネル接続処理
  # ============================================
  def subscribed
    # 認証チェック
    reject unless current_admin

    # 管理者専用のストリームに接続
    stream_for current_admin

    Rails.logger.info "Admin #{current_admin.id} subscribed to AdminChannel"

    # 接続完了通知
    transmit({
      type: "connection_established",
      admin_id: current_admin.id,
      timestamp: Time.current.iso8601
    })
  end

  def unsubscribed
    Rails.logger.info "Admin #{current_admin&.id} unsubscribed from AdminChannel"
  end

  # ============================================
  # CSV インポート進捗追跡の開始
  # ============================================
  def track_csv_import(data)
    job_id = data["job_id"]
    return reject_action("job_id required") unless job_id.present?

    # Redis からジョブ状況を取得
    redis = get_redis_connection
    return reject_action("Redis unavailable") unless redis

    status_key = "csv_import:#{job_id}"
    job_data = redis.hgetall(status_key)

    if job_data.empty?
      transmit({
        type: "csv_import_not_found",
        job_id: job_id,
        message: "指定されたインポートジョブが見つかりません",
        timestamp: Time.current.iso8601
      })
      return
    end

    # 現在の進捗状況を送信
    transmit({
      type: "csv_import_status",
      job_id: job_id,
      status: job_data["status"],
      progress: job_data["progress"]&.to_i || 0,
      started_at: job_data["started_at"],
      admin_id: job_data["admin_id"],
      file_path: job_data["file_path"],
      timestamp: Time.current.iso8601
    })
  end

  # ============================================
  # 在庫アラート通知の購読
  # ============================================
  def subscribe_stock_alerts(data)
    # 在庫アラート用のストリームに追加接続
    stream_from "stock_alerts"

    transmit({
      type: "stock_alerts_subscribed",
      message: "在庫アラート通知を開始しました",
      timestamp: Time.current.iso8601
    })
  end

  # ============================================
  # システム通知の購読
  # ============================================
  def subscribe_system_notifications(data)
    # システム通知用のストリームに追加接続
    stream_from "system_notifications"

    transmit({
      type: "system_notifications_subscribed",
      message: "システム通知を開始しました",
      timestamp: Time.current.iso8601
    })
  end

  # ============================================
  # エラーハンドリング
  # ============================================
  private

  def current_admin
    # Deviseの認証情報から管理者を取得
    @current_admin ||= env["warden"]&.user(:admin)
  end

  def reject_action(reason)
    transmit({
      type: "action_rejected",
      reason: reason,
      timestamp: Time.current.iso8601
    })
  end

  def get_redis_connection
    # ImportInventoriesJobと同じRedis接続ロジックを使用
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
end

# ============================================
# TODO: 将来の拡張機能（優先度：中）
# ============================================
# 1. マルチテナント対応
#    - 組織単位での通知チャンネル分離
#    - 権限ベースの通知フィルタリング
#
# 2. 通知設定のカスタマイズ
#    - 個別管理者の通知設定保存
#    - 通知頻度・タイミングの調整
#
# 3. パフォーマンス最適化
#    - バッチ通知による負荷軽減
#    - Redis Pub/Sub の効率的活用
#
# 4. 監視・分析機能
#    - 通知配信ログの記録
#    - リアルタイム接続状況の監視
#    - 通知効果の分析・改善提案
