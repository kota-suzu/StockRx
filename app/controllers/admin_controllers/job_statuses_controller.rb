# frozen_string_literal: true

module AdminControllers
  # ジョブのステータスを返すAPIコントローラー
  class JobStatusesController < BaseController
    before_action :authenticate_admin!

    # GET /admin/job_status/:id
    # ジョブのステータスをJSONで返す
    def show
      job_id = params[:id]

      # 現段階ではStimulusコントローラがシミュレートするため、実際のジョブステータスは不要
      # 実運用時にはRedisやデータベースからジョブステータスを取得する
      # job_status = Redis.current.get("csv_import:#{job_id}")

      # デモ用のダミー応答
      progress = rand(10..90) # ランダムな進捗状況

      render json: {
        job_id: job_id,
        progress: progress,
        status: "processing"
      }
    end
  end
end
