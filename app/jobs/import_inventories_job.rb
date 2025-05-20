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
    # TODO: Implement actual progress notification (e.g., ActionCable, Redis) for admin_id and job_id.
    notify_progress(0, admin_id, status_key)

    begin
      # ファイルを開いて行数をカウント（進捗表示用）
      total_lines = File.foreach(file_path).count - 1 # ヘッダーを除く

      # CSVインポート処理を実行
      # CsvImportable concernのimport_from_csvメソッドを利用
      # TODO: Consider making column_mapping and value_transformers configurable,
      # potentially passed as arguments to the job if CSV format varies.
      # For now, using a sensible default mapping for Inventory.
      # These should match the expected CSV format for inventory imports.
      inventory_column_mapping = {
        # Assuming CSV headers are lowercase and match model attributes directly.
        # If CSV headers are different (e.g., 'Product Name', 'Stock Quantity'),
        # update the keys here accordingly.
        "name" => "name",
        "quantity" => "quantity",
        "price" => "price",
        "status" => "status"
      }
      inventory_value_transformers = {
        "status" => ->(value) {
          # Example transformer: handles common string representations for status.
          normalized_value = value.to_s.downcase
          Inventory.statuses.key?(normalized_value) ? normalized_value : value
        }
      }
      import_options = {
        batch_size: 1000,
        column_mapping: inventory_column_mapping,
        value_transformers: inventory_value_transformers,
        skip_invalid: false # Consider if invalid records should halt the import or be skipped.
      }
      result = Inventory.import_from_csv(file_path, import_options)

      # 処理完了時間を計算
      duration = ((Time.current - start_time) / 1.second).round(2)

      # 処理完了を通知
      admin = Admin.find_by(id: admin_id)
      if admin.present?
        message = I18n.t("inventories.import.completed", duration: duration) + "\n" +
                 I18n.t("inventories.import.success", count: result[:imported]) + " " +
                 I18n.t("inventories.import.invalid_records", count: result[:invalid].size)

        # ActionCableで通知（実装されていれば）
        # TODO: Implement ActionCable notification for import completion.
        # Example: AdminChannel.broadcast_to(admin, { type: "csv_import_complete", message: message, job_id: job_id })

        # TODO: Implement email notification for import completion, especially for large imports.
        # Example: AdminMailer.csv_import_complete(admin, result, job_id).deliver_later if result[:processed_rows] > 1000
      end

      # 進捗100%を通知
      notify_progress(100, admin_id, status_key)

      # ログに記録
      Rails.logger.info "CSV import completed: #{result[:imported]} valid, #{result[:invalid].size} invalid. Duration: #{duration}s"

    rescue => e
      # エラーが発生した場合
      Rails.logger.error "CSV import error: #{e.message}\n#{e.backtrace.join("\n")}"

      # エラーを通知
      admin = Admin.find_by(id: admin_id)
      if admin.present?
        message = I18n.t("inventories.import.error", message: e.message)
        # TODO: Implement ActionCable notification for import error.
        # Example: AdminChannel.broadcast_to(admin, { type: "csv_import_error", message: message, job_id: job_id })
      end

      # エラーを再発生させる（失敗したジョブとして記録するため）
      raise e
    ensure
      # 一時ファイルを削除（開発環境以外）
      File.delete(file_path) if File.exist?(file_path) && !Rails.env.development? && defined?(file_path)
    end
  end

  private

  # 進捗状況を通知するメソッド
  # @param progress [Integer] 進捗割合（0-100）
  # @param admin_id [Integer] 管理者ID
  # @param status_key [String] 進捗ステータス保存用のキー
  def notify_progress(progress, admin_id, status_key)
    # ActionCableで通知（実装されていれば）
    # TODO: Implement ActionCable progress notification.
    # Example: AdminChannel.broadcast_to(Admin.find_by(id: admin_id), {
    #   type: "csv_import_progress",
    #   progress: progress,
    #   job_id: status_key.split(':').last # Assuming status_key is "csv_import:JOB_ID"
    # })

    # Redisに進捗状況を保存（Redisが設定されていれば）
    # TODO: Implement Redis progress storage if a polling mechanism is used by the frontend.
    # if defined?(RedisClient) && Rails.application.respond_to?(:redis) # For Rails 7.1+ with redis-rb
    #   Rails.application.redis.setex(status_key, 1.hour.to_i, progress.to_s)
    # end

    # ログに記録
    Rails.logger.info "CSV import progress: #{progress}% (Job ID: #{status_key.split(':').last}, Admin: #{admin_id})"
  end
end
