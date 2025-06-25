# frozen_string_literal: true

module AdminControllers
  # ジョブのステータスを返すAPIコントローラー
  # CLAUDE.md準拠: CSVインポートジョブのリアルタイム進捗追跡
  class JobStatusesController < BaseController
    # セキュリティ機能最適化: read-onlyアクションのみのため監査スキップ
    # メタ認知: ジョブステータス取得は機密データ操作ではないため
    # 横展開: 他の読み取り専用APIコントローラーでも同様の考慮が必要
    skip_around_action :audit_sensitive_data_access

    # TODO: 🟡 Phase 3（中）- リアルタイム監視機能強化
    # 優先度: 中（基本機能は動作確認済み）
    # 実装内容: WebSocket統合、進捗可視化、失敗通知システム
    # 理由: ユーザビリティ向上と運用効率化
    # 期待効果: CSVインポート処理の透明性向上、エラー早期発見
    # 工数見積: 1-2週間
    # 依存関係: ActionCable設定、フロントエンド改修

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
          # Redisにない場合はSidekiqの失敗ジョブから情報取得を試行
          sidekiq_status = get_job_status_from_sidekiq(job_id)

          if sidekiq_status
            render json: sidekiq_status
          else
            render json: {
              job_id: job_id,
              status: "not_found",
              error: "ジョブが見つかりません",
              progress: 0
            }, status: :not_found
          end
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

    # Sidekiqの失敗ジョブからステータス情報を取得
    def get_job_status_from_sidekiq(job_id)
      return nil unless defined?(Sidekiq)

      # 失敗ジョブを検索
      dead_set = Sidekiq::DeadSet.new
      retry_set = Sidekiq::RetrySet.new

      # 失敗ジョブの中から該当するジョブを検索
      failed_job = dead_set.find { |job| extract_job_id_from_args(job) == job_id } ||
                   retry_set.find { |job| extract_job_id_from_args(job) == job_id }

      return nil unless failed_job

      # 失敗ジョブの情報を構造化して返す
      {
        job_id: job_id,
        status: "failed",
        progress: 0,
        error_message: failed_job["error_message"] || "Unknown error",
        error_class: failed_job["error_class"] || "Unknown",
        failed_at: failed_job["failed_at"] ? Time.at(failed_job["failed_at"]).iso8601 : nil,
        retry_count: failed_job["retry_count"] || 0,
        file_name: extract_file_name_from_args(failed_job)
      }
    rescue => e
      Rails.logger.warn "Sidekiq job search failed: #{e.message}"
      nil
    end

    # ジョブの引数からジョブIDを抽出
    def extract_job_id_from_args(sidekiq_job)
      args = sidekiq_job["args"]
      return nil unless args.is_a?(Array) && args.first.is_a?(Hash)

      job_arguments = args.first["arguments"]
      return nil unless job_arguments.is_a?(Array) && job_arguments.length >= 4

      job_arguments[3] # 4番目の引数がjob_id
    rescue
      nil
    end

    # ジョブの引数からファイル名を抽出
    def extract_file_name_from_args(sidekiq_job)
      args = sidekiq_job["args"]
      return nil unless args.is_a?(Array) && args.first.is_a?(Hash)

      job_arguments = args.first["arguments"]
      return nil unless job_arguments.is_a?(Array) && job_arguments.length >= 1

      file_path = job_arguments[0]
      File.basename(file_path) if file_path
    rescue
      "Unknown file"
    end
  end
end
