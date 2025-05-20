# frozen_string_literal: true

class ImportInventoriesJob < ApplicationJob
  queue_as :default

  # 進捗通知用の定数
  PROGRESS_INCREMENTS = 10 # 進捗報告の間隔（％）

  # @param file_path [String] CSVファイルのパス
  # @param admin_id [Integer] インポートを実行した管理者のID
  # @param job_id [String] ジョブを識別するID
  def perform(file_path, admin_id, job_id = nil)
    # 処理開始時間を記録
    start_time = Time.current

    # 進捗状況のステータスを保存（将来的にはRedisやDBに保存することも検討）
    job_id = job_id || SecureRandom.uuid
    status_key = "csv_import:#{job_id}"

    # 処理開始を通知
    notify_progress(0, admin_id, status_key)

    begin
      # ファイルを開いて行数をカウント（進捗表示用）
      total_lines = File.foreach(file_path).count - 1 # ヘッダーを除く

      # CSVインポート処理を実行
      result = Inventory.import_from_csv(file_path, batch_size: 1000)

      # 処理完了時間を計算
      duration = ((Time.current - start_time) / 1.second).round(2)        # 処理完了を通知
        admin = Admin.find_by(id: admin_id)
        if admin.present?
          message = I18n.t("inventories.import.completed", duration: duration) + "\n" +
                   I18n.t("inventories.import.success", count: result[:imported]) + " " +
                   I18n.t("inventories.import.invalid_records", count: result[:invalid].size)

          # ActionCableで通知（実装されていれば）
          # ActionCable.server.broadcast("admin_#{admin_id}", { type: "csv_import_complete", message: message })

          # TODO: メール通知機能を追加（大きなインポート処理向け）
          # AdminMailer.csv_import_complete(admin, result).deliver_later
        end

        # 進捗100%を通知
        notify_progress(100, admin_id, status_key)

        # ログに記録
        Rails.logger.info "CSV import completed: #{result[:imported]} valid, #{result[:invalid].size} invalid. Duration: #{duration}s"

      # 一時ファイルを削除（必要に応じて）
      File.delete(file_path) if File.exist?(file_path) && !Rails.env.development?

    rescue => e
      # エラーが発生した場合
      Rails.logger.error "CSV import error: #{e.message}\n#{e.backtrace.join("\n")}"

      # エラーを通知
      admin = Admin.find_by(id: admin_id)
      if admin.present?
        message = I18n.t("inventories.import.error", message: e.message)
        # ActionCable.server.broadcast("admin_#{admin_id}", { type: "csv_import_error", message: message })
      end

      # 一時ファイルを削除（必要に応じて）
      File.delete(file_path) if File.exist?(file_path) && !Rails.env.development?

      # エラーを再発生させる（失敗したジョブとして記録するため）
      raise e
    end
  end

  private

  # 進捗状況を通知するメソッド
  # @param progress [Integer] 進捗割合（0-100）
  # @param admin_id [Integer] 管理者ID
  # @param status_key [String] 進捗ステータス保存用のキー
  def notify_progress(progress, admin_id, status_key)
    # ActionCableで通知（実装されていれば）
    # ActionCable.server.broadcast("admin_#{admin_id}", {
    #   type: "csv_import_progress",
    #   progress: progress,
    #   status_key: status_key
    # })

    # Redisに進捗状況を保存（Redisが設定されていれば）
    # if defined?(Redis) && Rails.application.config.respond_to?(:redis)
    #   redis = Rails.application.config.redis
    #   redis.set(status_key, progress.to_s)
    #   redis.expire(status_key, 1.hour.to_i) # 1時間後に自動削除
    # end

    # ログに記録
    Rails.logger.debug "CSV import progress: #{progress}% (admin: #{admin_id}, key: #{status_key})"
  end
end
