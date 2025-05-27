# frozen_string_literal: true

# ============================================
# Cleanup Old Logs Job
# ============================================
# 古いInventoryLogの定期クリーンアップ処理
# 定期実行：毎週日曜2時（sidekiq-scheduler経由）

class CleanupOldLogsJob < ApplicationJob
  # ============================================
  # Sidekiq Configuration
  # ============================================
  queue_as :default

  # Sidekiq specific options
  sidekiq_options retry: 1, backtrace: true, queue: :default

  # @param retention_days [Integer] ログ保持期間（デフォルト：90日）
  # @param batch_size [Integer] 一度に削除するレコード数（デフォルト：1000）
  def perform(retention_days = 90, batch_size = 1000)
    Rails.logger.info "Starting cleanup of old logs older than #{retention_days} days"

    cutoff_date = Date.current - retention_days.days
    total_deleted = 0

    begin
      # InventoryLogのクリーンアップ
      inventory_log_deleted = cleanup_inventory_logs(cutoff_date, batch_size)
      total_deleted += inventory_log_deleted

      # TODO: 将来的に他のログテーブルが追加された場合のクリーンアップ
      # audit_log_deleted = cleanup_audit_logs(cutoff_date, batch_size)
      # total_deleted += audit_log_deleted

      # 結果をログに記録
      Rails.logger.info({
        event: "log_cleanup_completed",
        retention_days: retention_days,
        cutoff_date: cutoff_date.iso8601,
        total_deleted: total_deleted,
        inventory_log_deleted: inventory_log_deleted
      }.to_json)

      # Redisのクリーンアップも実行
      cleanup_redis_data

      {
        total_deleted: total_deleted,
        cutoff_date: cutoff_date,
        retention_days: retention_days
      }

    rescue => e
      Rails.logger.error({
        event: "log_cleanup_failed",
        error_class: e.class.name,
        error_message: e.message,
        retention_days: retention_days
      }.to_json)
      raise e
    end
  end

  private

  def cleanup_inventory_logs(cutoff_date, batch_size)
    deleted_count = 0

    loop do
      # バッチサイズ分ずつ削除して、データベースへの負荷を軽減
      batch_deleted = InventoryLog.where("created_at < ?", cutoff_date)
                                  .limit(batch_size)
                                  .delete_all

      deleted_count += batch_deleted

      # 削除されたレコードがない場合は終了
      break if batch_deleted == 0

      # 次のバッチ処理までの短い待機（DBへの負荷軽減）
      sleep(0.1)
    end

    Rails.logger.info "Deleted #{deleted_count} old InventoryLog records"
    deleted_count
  end

  def cleanup_redis_data
    begin
      # CSVインポート進捗データのクリーンアップ
      cleanup_csv_import_progress

      # 古いSidekiq統計データのクリーンアップ
      cleanup_old_sidekiq_stats

      Rails.logger.info "Redis cleanup completed"

    rescue => e
      Rails.logger.warn "Redis cleanup failed: #{e.message}"
    end
  end

  def cleanup_csv_import_progress
    # 7日以上前のCSVインポート進捗データを削除
    cutoff_time = 7.days.ago

    if defined?(Sidekiq)
      Sidekiq.redis_pool.with do |redis|
        # csv_import:* キーのうち古いものを検索・削除
        keys = redis.keys("csv_import:*")
        keys.each do |key|
          created_at_str = redis.hget(key, "started_at")
          next unless created_at_str

          begin
            created_at = Time.parse(created_at_str)
            if created_at < cutoff_time
              redis.del(key)
              Rails.logger.debug "Deleted old CSV import progress key: #{key}"
            end
          rescue
            # パース失敗した場合は安全のため削除
            redis.del(key)
          end
        end
      end
    end
  end

  def cleanup_old_sidekiq_stats
    # Sidekiqの古い統計データをクリーンアップ
    if defined?(Sidekiq)
      Sidekiq.redis_pool.with do |redis|
        # 古いhistoryデータの削除（30日以上前）
        cutoff_timestamp = 30.days.ago.to_i

        %w[processed failed].each do |stat_type|
          key = "sidekiq:stat:#{stat_type}"

          # sorted setから古いエントリを削除
          redis.zremrangebyscore(key, 0, cutoff_timestamp)
        end
      end
    end
  end

  # TODO: 将来的な機能拡張
  # ============================================
  # 1. 高度なログ管理
  #    - ログの重要度別保持期間設定
  #    - 法的要件を満たすログ保管ポリシー
  #    - 圧縮アーカイブ機能
  #
  # 2. アーカイブ機能
  #    - 削除前の自動アーカイブ作成
  #    - S3/外部ストレージへの長期保管
  #    - アーカイブデータの検索機能
  #
  # 3. 監査・コンプライアンス対応
  #    - 削除ログの監査証跡記録
  #    - GDPR等の法的要件への対応
  #    - データ保護ポリシーの自動適用
  #
  # 4. パフォーマンス最適化
  #    - パーティショニングテーブル対応
  #    - インデックス最適化
  #    - 削除処理の並列化

  # def cleanup_audit_logs(cutoff_date, batch_size)
  #   # 将来的に監査ログテーブルが追加された場合の実装
  #   deleted_count = 0
  #
  #   loop do
  #     batch_deleted = AuditLog.where("created_at < ?", cutoff_date)
  #                             .limit(batch_size)
  #                             .delete_all
  #
  #     deleted_count += batch_deleted
  #     break if batch_deleted == 0
  #     sleep(0.1)
  #   end
  #
  #   Rails.logger.info "Deleted #{deleted_count} old AuditLog records"
  #   deleted_count
  # end
end
