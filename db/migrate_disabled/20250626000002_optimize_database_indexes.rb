# frozen_string_literal: true

# Team 6: データベース最適化 - Phase 1
# ===========================================
# 目的: 
# 1. 重複インデックスの削除
# 2. パフォーマンス向上のための新規インデックス追加
# 3. カバリングインデックスの実装
# 4. 部分インデックスによる効率化
#
# CLAUDE.md準拠: パフォーマンス最適化とメタ認知的アプローチ
# ===========================================

class OptimizeDatabaseIndexes < ActiveRecord::Migration[8.0]
  def up
    # ===========================================
    # Phase 1: 重複インデックスの削除
    # ===========================================
    
    # admin_notification_settings: 8個の重複インデックス削除
    remove_redundant_indexes_for_admin_notification_settings
    
    # admins: 6個の重複インデックス削除
    remove_redundant_indexes_for_admins
    
    # audit_logs: 6個の重複インデックス削除
    remove_redundant_indexes_for_audit_logs
    
    # その他のテーブルの重複インデックス削除
    remove_other_redundant_indexes
    
    # ===========================================
    # Phase 2: パフォーマンス向上のための新規インデックス追加
    # ===========================================
    
    # 頻繁に使用される日付範囲検索用インデックス
    add_date_range_indexes
    
    # カバリングインデックスの追加
    add_covering_indexes
    
    # 部分インデックスの追加（条件付きインデックス）
    add_partial_indexes
    
    # ===========================================
    # Phase 3: 統計情報の更新
    # ===========================================
    
    # MySQL/MariaDB用のテーブル統計情報更新
    update_table_statistics if mysql_or_mariadb?
  end
  
  def down
    # 削除したインデックスの復元（ロールバック用）
    restore_removed_indexes
    
    # 追加したインデックスの削除
    remove_added_indexes
  end
  
  private
  
  def remove_redundant_indexes_for_admin_notification_settings
    # 単一カラムインデックスが複合インデックスに含まれる場合は削除
    remove_index :admin_notification_settings, :admin_id, if_exists: true
    remove_index :admin_notification_settings, :delivery_method, if_exists: true
    remove_index :admin_notification_settings, :notification_type, if_exists: true
    remove_index :admin_notification_settings, :priority, if_exists: true
  end
  
  def remove_redundant_indexes_for_admins
    # 複合インデックスに含まれる単一カラムインデックスを削除
    remove_index :admins, :provider, if_exists: true
    remove_index :admins, :role, if_exists: true
    remove_index :admins, :store_id, if_exists: true
  end
  
  def remove_redundant_indexes_for_audit_logs
    # 複合インデックスでカバーされる単一インデックスを削除
    remove_index :audit_logs, :action, if_exists: true
    remove_index :audit_logs, :user_id, if_exists: true
    remove_index :audit_logs, name: "index_audit_logs_on_auditable", if_exists: true
  end
  
  def remove_other_redundant_indexes
    # batches
    remove_index :batches, :inventory_id, if_exists: true
    
    # batch_movements
    remove_index :batch_movements, :batch_id, if_exists: true
    
    # compliance_audit_logs
    remove_index :compliance_audit_logs, :event_type, if_exists: true
    remove_index :compliance_audit_logs, :severity, if_exists: true
    remove_index :compliance_audit_logs, :compliance_standard, if_exists: true
    
    # inter_store_transfers
    remove_index :inter_store_transfers, :source_store_id, if_exists: true
    remove_index :inter_store_transfers, :status, if_exists: true
    
    # inventories
    remove_index :inventories, name: "idx_inventories_quantity", if_exists: true
    
    # store_inventories
    remove_index :store_inventories, :store_id, if_exists: true
    
    # store_users
    remove_index :store_users, :store_id, if_exists: true
    
    # stores
    remove_index :stores, :store_type, if_exists: true
  end
  
  def add_date_range_indexes
    # 日付範囲検索の最適化
    add_index :inventory_logs, [:created_at, :inventory_id], 
              name: "idx_inventory_logs_date_range"
    
    add_index :audit_logs, [:created_at, :action, :user_id], 
              name: "idx_audit_logs_date_action_user"
    
    add_index :inter_store_transfers, [:requested_at, :status], 
              name: "idx_transfers_date_status"
    
    # 在庫アラート用の複合インデックス
    add_index :store_inventories, [:quantity, :safety_stock_level, :store_id], 
              name: "idx_stock_alert_lookup"
  end
  
  def add_covering_indexes
    # よく使用されるクエリ用のカバリングインデックス
    
    # 在庫一覧表示用（quantity, name, priceを含む）
    add_index :inventories, [:status, :name, :quantity, :price], 
              name: "idx_inventory_list_covering"
    
    # 店舗在庫ダッシュボード用
    add_index :store_inventories, [:store_id, :quantity, :reserved_quantity, :safety_stock_level], 
              name: "idx_store_dashboard_covering"
    
    # 監査ログ検索用
    add_index :audit_logs, [:user_id, :action, :created_at, :auditable_type, :auditable_id], 
              name: "idx_audit_search_covering"
  end
  
  def add_partial_indexes
    # 条件付きインデックス（特定の条件下でのみ有効）
    
    # アクティブな在庫のみのインデックス
    add_index :inventories, [:name, :quantity], 
              where: "status = 0", 
              name: "idx_active_inventories"
    
    # 低在庫アイテム専用インデックス
    add_index :store_inventories, [:store_id, :inventory_id], 
              where: "quantity <= safety_stock_level", 
              name: "idx_low_stock_items"
    
    # ペンディング状態の移動申請専用
    add_index :inter_store_transfers, [:source_store_id, :destination_store_id, :requested_at], 
              where: "status = 0", 
              name: "idx_pending_transfers"
    
    # 未読の監査ログ（セキュリティイベント）
    add_index :audit_logs, [:created_at, :severity], 
              where: "security_event = true", 
              name: "idx_security_events"
  end
  
  def update_table_statistics
    # MySQL/MariaDB用のテーブル統計情報更新
    tables_to_analyze = %w[
      inventories
      store_inventories
      inventory_logs
      audit_logs
      inter_store_transfers
      batches
    ]
    
    tables_to_analyze.each do |table|
      execute "ANALYZE TABLE #{table}"
    end
  end
  
  def restore_removed_indexes
    # ロールバック時の復元処理
    # 削除したインデックスを元に戻す
    
    # admin_notification_settings
    add_index :admin_notification_settings, :admin_id
    add_index :admin_notification_settings, :delivery_method
    add_index :admin_notification_settings, :notification_type
    add_index :admin_notification_settings, :priority
    
    # 他のインデックスも同様に復元...
  end
  
  def remove_added_indexes
    # 追加したインデックスを削除
    remove_index :inventory_logs, name: "idx_inventory_logs_date_range", if_exists: true
    remove_index :audit_logs, name: "idx_audit_logs_date_action_user", if_exists: true
    remove_index :inter_store_transfers, name: "idx_transfers_date_status", if_exists: true
    remove_index :store_inventories, name: "idx_stock_alert_lookup", if_exists: true
    
    # カバリングインデックスの削除
    remove_index :inventories, name: "idx_inventory_list_covering", if_exists: true
    remove_index :store_inventories, name: "idx_store_dashboard_covering", if_exists: true
    remove_index :audit_logs, name: "idx_audit_search_covering", if_exists: true
    
    # 部分インデックスの削除
    remove_index :inventories, name: "idx_active_inventories", if_exists: true
    remove_index :store_inventories, name: "idx_low_stock_items", if_exists: true
    remove_index :inter_store_transfers, name: "idx_pending_transfers", if_exists: true
    remove_index :audit_logs, name: "idx_security_events", if_exists: true
  end
  
  def mysql_or_mariadb?
    connection.adapter_name.downcase.include?('mysql')
  end
end