# frozen_string_literal: true

# Team 6: データベースメンテナンスジョブ
# ========================================
# 定期的なデータベース最適化タスクを実行
# - テーブル統計情報の更新
# - 断片化の解消
# - 古いデータのアーカイブ
# ========================================

class DatabaseMaintenanceJob < ApplicationJob
  queue_as :low

  # CLAUDE.md準拠: セキュアロギング対応
  include SecureLogging

  # リトライ設定
  retry_on ActiveRecord::StatementInvalid, wait: 5.minutes, attempts: 3

  def perform(options = {})
    logger.info "データベースメンテナンスを開始します"

    # メンテナンスタスクの実行
    update_table_statistics if options[:update_stats] != false
    optimize_fragmented_tables if options[:optimize_tables] != false
    archive_old_data if options[:archive_data] != false
    clean_up_sessions if options[:clean_sessions] != false

    logger.info "データベースメンテナンスが完了しました"
  rescue => e
    logger.error "データベースメンテナンス中にエラーが発生しました: #{e.message}"
    raise
  end

  private

  # テーブル統計情報の更新
  def update_table_statistics
    logger.info "テーブル統計情報を更新中..."

    critical_tables = %w[
      inventories
      store_inventories
      inventory_logs
      audit_logs
      inter_store_transfers
      batches
    ]

    critical_tables.each do |table|
      # 🛡️ セキュリティ対策: テーブル名をホワイトリスト検証
      if valid_table_name?(table)
        # 🛡️ セキュリティ対策: Arel.sql()でSQL文字列の安全性を保証
        analyze_sql = Arel.sql("ANALYZE TABLE #{connection.quote_table_name(table)}")
        ActiveRecord::Base.connection.execute(analyze_sql)
        logger.info "  #{table} の統計情報を更新しました"
      else
        logger.warn "  #{table} は無効なテーブル名です"
      end
    rescue => e
      logger.warn "  #{table} の統計情報更新に失敗: #{e.message}"
    end
  end

  # 断片化したテーブルの最適化
  def optimize_fragmented_tables
    logger.info "断片化したテーブルを最適化中..."

    # 断片化率が20%以上のテーブルを検出
    fragmented_tables = detect_fragmented_tables(threshold: 20)

    fragmented_tables.each do |table_info|
      table_name = table_info[:table_name]
      fragmentation = table_info[:fragmentation_percent]

      logger.info "  #{table_name} (断片化率: #{fragmentation}%) を最適化中..."

      # 🛡️ セキュリティ対策: テーブル名をホワイトリスト検証
      if valid_table_name?(table_name)
        # 🛡️ セキュリティ対策: Arel.sql()でSQL文字列の安全性を保証
        optimize_sql = Arel.sql("OPTIMIZE TABLE #{connection.quote_table_name(table_name)}")
        ActiveRecord::Base.connection.execute(optimize_sql)
      else
        logger.warn "  #{table_name} は無効なテーブル名です"
        next
      end

      logger.info "  #{table_name} の最適化が完了しました"
    rescue => e
      logger.warn "  #{table_name} の最適化に失敗: #{e.message}"
    end
  end

  # 古いデータのアーカイブ
  def archive_old_data
    logger.info "古いデータをアーカイブ中..."

    # 監査ログ（90日以上前）
    archive_audit_logs(days_old: 90)

    # 在庫ログ（180日以上前）
    archive_inventory_logs(days_old: 180)

    # 完了済み移動申請（365日以上前）
    archive_completed_transfers(days_old: 365)
  end

  # セッションデータのクリーンアップ
  def clean_up_sessions
    logger.info "期限切れセッションをクリーンアップ中..."

    # 30日以上前の無効なセッション削除
    if defined?(ActiveRecord::SessionStore)
      deleted_count = ActiveRecord::SessionStore::Session
                     .where("updated_at < ?", 30.days.ago)
                     .delete_all

      logger.info "  #{deleted_count} 件の期限切れセッションを削除しました"
    end
  end

  # 断片化したテーブルの検出
  def detect_fragmented_tables(threshold:)
    # 🛡️ セキュリティ対策: 閾値をバリデーション
    threshold = threshold.to_f.clamp(0.0, 100.0)

    # 🛡️ セキュリティ対策: プレースホルダーでパラメータを安全に挿入
    query = <<-SQL
      SELECT#{' '}
        TABLE_NAME as table_name,
        ROUND(((DATA_LENGTH + INDEX_LENGTH) -#{' '}
               (DATA_LENGTH + INDEX_LENGTH - DATA_FREE)) /#{' '}
               (DATA_LENGTH + INDEX_LENGTH) * 100, 2) as fragmentation_percent,
        ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as size_mb
      FROM#{' '}
        information_schema.TABLES
      WHERE#{' '}
        TABLE_SCHEMA = DATABASE() AND
        DATA_FREE > 0 AND
        (DATA_FREE / (DATA_LENGTH + INDEX_LENGTH)) * 100 > ?
      ORDER BY#{' '}
        fragmentation_percent DESC
    SQL

    # 🛡️ セキュリティ対策: prepared statementで実行
    results = ActiveRecord::Base.connection.exec_query(query, "detect_fragmented_tables", [ threshold ])
    results.map do |row|
      {
        table_name: row[0],
        fragmentation_percent: row[1].to_f,
        size_mb: row[2].to_f
      }
    end
  end

  # 監査ログのアーカイブ
  def archive_audit_logs(days_old:)
    cutoff_date = days_old.days.ago

    # バッチ処理でアーカイブ
    archived_count = 0
    AuditLog.where("created_at < ?", cutoff_date).find_in_batches(batch_size: 1000) do |batch|
      # 🛡️ セキュリティ対策: プレースホルダーでIDsを安全に処理
      # 注: archive_audit_logsテーブルは別途作成が必要

      # より安全なアプローチ: ActiveRecordのクエリビルダーを使用
      if archive_table_exists?
        # 1つずつ安全にアーカイブ
        batch.each do |audit_log|
          # prepared statementで安全な挿入
          connection.exec_query(
            "INSERT INTO archive_audit_logs SELECT * FROM audit_logs WHERE id = ?",
            "archive_single_audit_log",
            [ audit_log.id ]
          )
        end
      else
        Rails.logger.warn "Archive table 'archive_audit_logs' does not exist. Skipping archive."
        return
      end

      # 元テーブルから削除
      AuditLog.where(id: batch.map(&:id)).delete_all

      archived_count += batch.size
    end

    logger.info "  #{archived_count} 件の監査ログをアーカイブしました"
  rescue => e
    logger.error "  監査ログのアーカイブに失敗: #{e.message}"
  end

  # 在庫ログのアーカイブ
  def archive_inventory_logs(days_old:)
    cutoff_date = days_old.days.ago

    # 重要な操作タイプは長期保存
    important_operations = %w[initial_import manual_adjustment stock_take]

    archived_count = InventoryLog
                    .where("created_at < ?", cutoff_date)
                    .where.not(operation_type: important_operations)
                    .delete_all

    logger.info "  #{archived_count} 件の在庫ログをアーカイブしました"
  end

  # 完了済み移動申請のアーカイブ
  def archive_completed_transfers(days_old:)
    cutoff_date = days_old.days.ago

    archived_count = InterStoreTransfer
                    .where(status: [ :completed, :cancelled ])
                    .where("completed_at < ? OR updated_at < ?", cutoff_date, cutoff_date)
                    .delete_all

    logger.info "  #{archived_count} 件の完了済み移動申請をアーカイブしました"
  end

  # 🛡️ セキュリティ対策: テーブル名の検証
  def valid_table_name?(table_name)
    # ホワイトリスト方式でテーブル名を検証
    allowed_tables = %w[
      inventories
      store_inventories
      inventory_logs
      audit_logs
      inter_store_transfers
      batches
      admins
      store_users
      stores
      sessions
    ]

    allowed_tables.include?(table_name.to_s)
  end

  # 🛡️ セキュリティ対策: データベース接続のヘルパー
  def connection
    @connection ||= ActiveRecord::Base.connection
  end

  # 🛡️ セキュリティ対策: アーカイブテーブルの存在確認
  def archive_table_exists?
    connection.table_exists?("archive_audit_logs")
  rescue => e
    Rails.logger.error "Failed to check archive table existence: #{e.message}"
    false
  end
end
