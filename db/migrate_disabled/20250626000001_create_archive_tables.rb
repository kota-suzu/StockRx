# frozen_string_literal: true

# Team 6: データアーカイブテーブル作成
# ====================================
# 古いデータを本番テーブルから分離してパフォーマンスを向上
# - 監査ログのアーカイブ（90日以上）
# - 在庫ログのアーカイブ（180日以上）
# - 移動申請のアーカイブ（1年以上）
# ====================================

class CreateArchiveTables < ActiveRecord::Migration[8.0]
  def up
    # 監査ログアーカイブテーブル
    create_table :archive_audit_logs, comment: "90日以上前の監査ログアーカイブ" do |t|
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.bigint :user_id
      t.string :action, null: false
      t.text :message, null: false
      t.text :details
      t.string :ip_address
      t.text :user_agent
      t.string :operation_source
      t.string :operation_type
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.string :severity, comment: "イベントの重要度 (info, warning, critical)"
      t.boolean :security_event, default: false, comment: "セキュリティイベントフラグ"
      t.string :session_id, comment: "セッションID"
      t.string :user_type
      t.datetime :archived_at, null: false, comment: "アーカイブ日時"
      
      # パーティション用のインデックス（月別）
      t.index [:created_at], name: "idx_archive_audit_logs_created_at"
      t.index [:archived_at], name: "idx_archive_audit_logs_archived_at"
      t.index [:auditable_type, :auditable_id], name: "idx_archive_audit_logs_auditable"
      t.index [:user_type, :user_id], name: "idx_archive_audit_logs_user"
      t.index [:action], name: "idx_archive_audit_logs_action"
      t.index [:security_event], name: "idx_archive_audit_logs_security", where: "security_event = true"
    end
    
    # 在庫ログアーカイブテーブル
    create_table :archive_inventory_logs, comment: "180日以上前の在庫ログアーカイブ" do |t|
      t.bigint :inventory_id, null: false
      t.integer :delta, null: false
      t.string :operation_type, null: false
      t.integer :previous_quantity, null: false
      t.integer :current_quantity, null: false
      t.text :note
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.bigint :user_id
      t.datetime :archived_at, null: false, comment: "アーカイブ日時"
      
      # インデックス
      t.index [:created_at], name: "idx_archive_inventory_logs_created_at"
      t.index [:archived_at], name: "idx_archive_inventory_logs_archived_at"
      t.index [:inventory_id], name: "idx_archive_inventory_logs_inventory_id"
      t.index [:operation_type], name: "idx_archive_inventory_logs_operation_type"
      t.index [:user_id], name: "idx_archive_inventory_logs_user_id"
    end
    
    # 移動申請アーカイブテーブル
    create_table :archive_inter_store_transfers, comment: "1年以上前の完了済み移動申請アーカイブ" do |t|
      t.bigint :source_store_id, null: false, comment: "移動元店舗ID"
      t.bigint :destination_store_id, null: false, comment: "移動先店舗ID"
      t.bigint :inventory_id, null: false, comment: "商品ID"
      t.integer :quantity, null: false, comment: "移動数量"
      t.integer :status, default: 0, null: false, comment: "移動ステータス"
      t.integer :priority, default: 0, null: false, comment: "優先度"
      t.text :reason, comment: "移動理由・備考"
      t.bigint :requested_by_id, null: false, comment: "申請者（Admin ID）"
      t.bigint :approved_by_id, comment: "承認者（Admin ID）"
      t.datetime :requested_at, null: false, comment: "申請日時"
      t.datetime :approved_at, comment: "承認日時"
      t.datetime :completed_at, comment: "完了日時"
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.datetime :shipped_at, comment: "出荷日時"
      t.string :requested_by_type
      t.string :approved_by_type
      t.integer :shipped_by_id
      t.string :shipped_by_type
      t.integer :completed_by_id
      t.string :completed_by_type
      t.integer :cancelled_by_id
      t.string :cancelled_by_type
      t.text :notes
      t.date :requested_delivery_date
      t.datetime :archived_at, null: false, comment: "アーカイブ日時"
      
      # インデックス
      t.index [:archived_at], name: "idx_archive_transfers_archived_at"
      t.index [:source_store_id], name: "idx_archive_transfers_source_store"
      t.index [:destination_store_id], name: "idx_archive_transfers_destination_store"
      t.index [:inventory_id], name: "idx_archive_transfers_inventory"
      t.index [:status], name: "idx_archive_transfers_status"
      t.index [:completed_at], name: "idx_archive_transfers_completed_at"
      t.index [:requested_at], name: "idx_archive_transfers_requested_at"
    end
    
    # パーティション化（MySQL 8.0以降）
    if mysql_version >= 8.0
      add_partitioning_to_archive_tables
    end
  end
  
  def down
    drop_table :archive_inter_store_transfers, if_exists: true
    drop_table :archive_inventory_logs, if_exists: true
    drop_table :archive_audit_logs, if_exists: true
  end
  
  private
  
  def mysql_version
    version_string = connection.execute("SELECT VERSION()").first[0]
    version_string.match(/(\d+\.\d+)/)[1].to_f
  rescue
    5.7 # デフォルト値
  end
  
  def add_partitioning_to_archive_tables
    # 監査ログアーカイブのパーティショニング（月別）
    execute <<-SQL
      ALTER TABLE archive_audit_logs 
      PARTITION BY RANGE (YEAR(created_at) * 100 + MONTH(created_at)) (
        PARTITION p_archive_202501 VALUES LESS THAN (202502),
        PARTITION p_archive_202502 VALUES LESS THAN (202503),
        PARTITION p_archive_202503 VALUES LESS THAN (202504),
        PARTITION p_archive_202504 VALUES LESS THAN (202505),
        PARTITION p_archive_202505 VALUES LESS THAN (202506),
        PARTITION p_archive_202506 VALUES LESS THAN (202507),
        PARTITION p_archive_202507 VALUES LESS THAN (202508),
        PARTITION p_archive_202508 VALUES LESS THAN (202509),
        PARTITION p_archive_202509 VALUES LESS THAN (202510),
        PARTITION p_archive_202510 VALUES LESS THAN (202511),
        PARTITION p_archive_202511 VALUES LESS THAN (202512),
        PARTITION p_archive_202512 VALUES LESS THAN (202601),
        PARTITION p_archive_future VALUES LESS THAN MAXVALUE
      )
    SQL
    
    # 在庫ログアーカイブのパーティショニング（四半期別）
    execute <<-SQL
      ALTER TABLE archive_inventory_logs 
      PARTITION BY RANGE (YEAR(created_at) * 100 + QUARTER(created_at)) (
        PARTITION p_inv_archive_20251 VALUES LESS THAN (20252),
        PARTITION p_inv_archive_20252 VALUES LESS THAN (20253),
        PARTITION p_inv_archive_20253 VALUES LESS THAN (20254),
        PARTITION p_inv_archive_20254 VALUES LESS THAN (20261),
        PARTITION p_inv_archive_future VALUES LESS THAN MAXVALUE
      )
    SQL
    
    # 移動申請アーカイブのパーティショニング（年別）
    execute <<-SQL
      ALTER TABLE archive_inter_store_transfers 
      PARTITION BY RANGE (YEAR(completed_at)) (
        PARTITION p_transfer_archive_2025 VALUES LESS THAN (2026),
        PARTITION p_transfer_archive_2026 VALUES LESS THAN (2027),
        PARTITION p_transfer_archive_2027 VALUES LESS THAN (2028),
        PARTITION p_transfer_archive_future VALUES LESS THAN MAXVALUE
      )
    SQL
  end
end