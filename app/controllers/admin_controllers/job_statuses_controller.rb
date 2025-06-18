# frozen_string_literal: true

module AdminControllers
  # ジョブのステータスを返すAPIコントローラー
  # CLAUDE.md準拠: CSVインポートジョブのリアルタイム進捗追跡
  class JobStatusesController < BaseController
    # セキュリティ機能最適化: read-onlyアクションのみのため監査スキップ
    # メタ認知: ジョブステータス取得は機密データ操作ではないため
    # 横展開: 他の読み取り専用APIコントローラーでも同様の考慮が必要
    skip_around_action :audit_sensitive_data_access
    
    before_action :authenticate_admin!

    # GET /admin/job_status/:id
    # ジョブのステータスをJSONで返す
    def show
      job_id = params[:id]

      begin
        # Redis からジョブステータスを取得
        job_status = get_job_status_from_redis(job_id)

        if job_status
          render json: job_status
        else
          render json: {
            job_id: job_id,
            status: "not_found",
            error: "ジョブが見つかりません",
            progress: 0
          }, status: :not_found
        end

      rescue => e
        Rails.logger.error "Job status retrieval error: #{e.message}"

        render json: {
          job_id: job_id,
          status: "error",
          error: "ステータス取得中にエラーが発生しました",
          progress: 0
        }, status: :internal_server_error
      end
    end

    private

    # Redis からジョブステータスを取得
    def get_job_status_from_redis(job_id)
      redis = get_redis_connection
      return nil unless redis

      status_key = "csv_import:#{job_id}"

      begin
        # ハッシュからすべてのフィールドを取得
        status_data = redis.hgetall(status_key)

        return nil if status_data.empty?

        # CLAUDE.md準拠: 構造化されたステータス情報
        {
          job_id: job_id,
          status: status_data["status"] || "unknown",
          progress: status_data["progress"]&.to_i || 0,
          started_at: status_data["started_at"],
          completed_at: status_data["completed_at"],
          failed_at: status_data["failed_at"],
          file_name: status_data["file_name"],
          admin_id: status_data["admin_id"],
          valid_count: status_data["valid_count"]&.to_i || 0,
          invalid_count: status_data["invalid_count"]&.to_i || 0,
          duration: status_data["duration"]&.to_f || 0,
          error_message: status_data["error_message"],
          message: status_data["message"]
        }

      rescue Redis::CannotConnectError => e
        Rails.logger.warn "Redis connection failed: #{e.message}"
        nil
      end
    end

    # Redis接続を取得
    def get_redis_connection
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
