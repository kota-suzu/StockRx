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
      ActiveRecord::Base.connection.execute("ANALYZE TABLE #{table}")
      logger.info "  #{table} の統計情報を更新しました"
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
      
      # OPTIMIZE TABLEの実行（InnoDBの場合は再構築される）
      ActiveRecord::Base.connection.execute("OPTIMIZE TABLE #{table_name}")
      
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
    query = <<-SQL
      SELECT 
        TABLE_NAME as table_name,
        ROUND(((DATA_LENGTH + INDEX_LENGTH) - 
               (DATA_LENGTH + INDEX_LENGTH - DATA_FREE)) / 
               (DATA_LENGTH + INDEX_LENGTH) * 100, 2) as fragmentation_percent,
        ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as size_mb
      FROM 
        information_schema.TABLES
      WHERE 
        TABLE_SCHEMA = DATABASE() AND
        DATA_FREE > 0 AND
        (DATA_FREE / (DATA_LENGTH + INDEX_LENGTH)) * 100 > #{threshold}
      ORDER BY 
        fragmentation_percent DESC
    SQL
    
    results = ActiveRecord::Base.connection.execute(query)
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
      # アーカイブテーブルへの移動
      # 注: archive_audit_logsテーブルは別途作成が必要
      insert_sql = <<-SQL
        INSERT INTO archive_audit_logs 
        SELECT * FROM audit_logs 
        WHERE id IN (#{batch.map(&:id).join(',')})
      SQL
      
      ActiveRecord::Base.connection.execute(insert_sql)
      
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
                    .where(status: [:completed, :cancelled])
                    .where("completed_at < ? OR updated_at < ?", cutoff_date, cutoff_date)
                    .delete_all
    
    logger.info "  #{archived_count} 件の完了済み移動申請をアーカイブしました"
  end
end