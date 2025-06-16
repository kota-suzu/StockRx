# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_06_17_070153) do
  create_table "admin_notification_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "admin_id", null: false
    t.string "notification_type", null: false, comment: "通知タイプ（csv_import, stock_alert等）"
    t.string "delivery_method", null: false, comment: "配信方法（email, actioncable等）"
    t.boolean "enabled", default: true, null: false, comment: "通知の有効/無効"
    t.integer "priority", default: 1, null: false, comment: "優先度（0:低 1:中 2:高 3:緊急）"
    t.integer "frequency_minutes", comment: "通知頻度制限（分）"
    t.datetime "last_sent_at", comment: "最後の通知送信日時"
    t.integer "sent_count", default: 0, null: false, comment: "送信回数"
    t.datetime "active_from", comment: "有効期間開始日時"
    t.datetime "active_until", comment: "有効期間終了日時"
    t.text "settings_json", comment: "詳細設定（JSON形式）"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id", "notification_type", "delivery_method"], name: "idx_admin_notification_unique", unique: true
    t.index ["admin_id"], name: "index_admin_notification_settings_on_admin_id"
    t.index ["delivery_method", "enabled"], name: "idx_delivery_method_enabled"
    t.index ["delivery_method"], name: "index_admin_notification_settings_on_delivery_method"
    t.index ["enabled"], name: "index_admin_notification_settings_on_enabled"
    t.index ["last_sent_at"], name: "index_admin_notification_settings_on_last_sent_at"
    t.index ["notification_type", "enabled"], name: "idx_notification_type_enabled"
    t.index ["notification_type"], name: "index_admin_notification_settings_on_notification_type"
    t.index ["priority", "enabled"], name: "idx_priority_enabled"
    t.index ["priority"], name: "index_admin_notification_settings_on_priority"
  end

  create_table "admins", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "uid"
    t.bigint "store_id", comment: "所属店舗ID（本部管理者の場合はNULL）"
    t.string "role", limit: 30, default: "store_user", null: false, comment: "管理者役割（headquarters_admin, store_manager, pharmacist, store_user）"
    t.string "name", limit: 50, comment: "管理者名"
    t.boolean "active", default: true, null: false, comment: "アカウント有効フラグ"
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["provider", "uid"], name: "index_admins_on_provider_and_uid", unique: true
    t.index ["provider"], name: "index_admins_on_provider"
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
    t.index ["role", "active"], name: "index_admins_on_role_and_active", comment: "役割・有効状態複合検索"
    t.index ["role"], name: "index_admins_on_role", comment: "役割別検索最適化"
    t.index ["store_id", "role"], name: "index_admins_on_store_id_and_role", comment: "店舗・役割複合検索"
    t.index ["store_id"], name: "index_admins_on_store_id"
    t.index ["unlock_token"], name: "index_admins_on_unlock_token", unique: true
  end

  create_table "audit_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "auditable_type", null: false
    t.bigint "auditable_id", null: false
    t.bigint "user_id"
    t.string "action", null: false
    t.text "message", null: false
    t.text "details"
    t.string "ip_address"
    t.text "user_agent"
    t.string "operation_source"
    t.string "operation_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "severity", comment: "イベントの重要度 (info, warning, critical)"
    t.boolean "security_event", default: false, comment: "セキュリティイベントフラグ"
    t.string "session_id", comment: "セッションID"
    t.index ["action", "created_at"], name: "index_audit_logs_on_action_and_created_at"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["security_event"], name: "index_audit_logs_on_security_event"
    t.index ["severity"], name: "index_audit_logs_on_severity"
    t.index ["user_id", "created_at"], name: "index_audit_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "batches", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.string "lot_code", null: false
    t.date "expires_on"
    t.integer "quantity", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_on"], name: "index_batches_on_expires_on"
    t.index ["inventory_id", "lot_code"], name: "uniq_inventory_lot", unique: true
    t.index ["inventory_id"], name: "index_batches_on_inventory_id"
  end

  create_table "identities", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "admin_id", null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "name"
    t.string "email"
    t.string "image_url"
    t.json "raw_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id", "provider"], name: "index_identities_on_admin_id_and_provider", unique: true
    t.index ["admin_id"], name: "index_identities_on_admin_id"
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
  end

  create_table "inter_store_transfers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "source_store_id", null: false, comment: "移動元店舗ID"
    t.bigint "destination_store_id", null: false, comment: "移動先店舗ID"
    t.bigint "inventory_id", null: false, comment: "商品ID"
    t.integer "quantity", null: false, comment: "移動数量"
    t.integer "status", default: 0, null: false, comment: "移動ステータス（0:pending, 1:approved, 2:rejected, 3:in_transit, 4:completed, 5:cancelled）"
    t.integer "priority", default: 0, null: false, comment: "優先度（0:normal, 1:urgent, 2:emergency）"
    t.text "reason", comment: "移動理由・備考"
    t.bigint "requested_by_id", null: false, comment: "申請者（Admin ID）"
    t.bigint "approved_by_id", comment: "承認者（Admin ID）"
    t.datetime "requested_at", null: false, comment: "申請日時"
    t.datetime "approved_at", comment: "承認日時"
    t.datetime "completed_at", comment: "完了日時"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_inter_store_transfers_on_approved_by_id", comment: "承認者別検索最適化"
    t.index ["destination_store_id"], name: "index_inter_store_transfers_on_destination_store_id", comment: "移動先店舗検索最適化"
    t.index ["inventory_id"], name: "index_inter_store_transfers_on_inventory_id"
    t.index ["requested_at"], name: "index_inter_store_transfers_on_requested_at", comment: "申請日時検索最適化"
    t.index ["requested_by_id"], name: "index_inter_store_transfers_on_requested_by_id", comment: "申請者別検索最適化"
    t.index ["source_store_id", "status", "requested_at"], name: "idx_source_status_date", comment: "店舗別ステータス・日時複合検索"
    t.index ["source_store_id"], name: "index_inter_store_transfers_on_source_store_id", comment: "移動元店舗検索最適化"
    t.index ["status", "priority"], name: "index_inter_store_transfers_on_status_and_priority", comment: "ステータス・優先度複合検索"
    t.index ["status"], name: "index_inter_store_transfers_on_status", comment: "ステータス別検索最適化"
    t.check_constraint "`quantity` > 0", name: "chk_positive_quantity"
    t.check_constraint "`source_store_id` <> `destination_store_id`", name: "chk_different_stores"
  end

  create_table "inventories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "quantity", default: 0, null: false
    t.decimal "price", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "batches_count", default: 0, null: false
    t.integer "inventory_logs_count", default: 0, null: false
    t.integer "shipments_count", default: 0, null: false
    t.integer "receipts_count", default: 0, null: false
    t.index ["batches_count"], name: "index_inventories_on_batches_count"
    t.index ["inventory_logs_count"], name: "index_inventories_on_inventory_logs_count"
    t.index ["name"], name: "index_inventories_on_name"
    t.index ["receipts_count"], name: "index_inventories_on_receipts_count"
    t.index ["shipments_count"], name: "index_inventories_on_shipments_count"
  end

  create_table "inventory_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.integer "delta", null: false
    t.string "operation_type", null: false
    t.integer "previous_quantity", null: false
    t.integer "current_quantity", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["created_at"], name: "index_inventory_logs_on_created_at"
    t.index ["inventory_id"], name: "index_inventory_logs_on_inventory_id"
    t.index ["operation_type"], name: "index_inventory_logs_on_operation_type"
    t.index ["user_id"], name: "index_inventory_logs_on_user_id"
  end

  create_table "receipts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.integer "quantity"
    t.string "source"
    t.date "receipt_date"
    t.integer "receipt_status"
    t.string "batch_number"
    t.string "purchase_order"
    t.decimal "cost_per_unit", precision: 10
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id"], name: "index_receipts_on_inventory_id"
  end

  create_table "report_files", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "report_type", null: false, comment: "レポート種別 (monthly_summary, inventory_analysis)"
    t.string "file_format", null: false, comment: "ファイル形式 (excel, pdf)"
    t.date "report_period", null: false, comment: "レポート対象期間 (YYYY-MM-01形式)"
    t.string "file_name", null: false, comment: "ファイル名"
    t.string "file_path", null: false, comment: "ファイル保存パス"
    t.string "storage_type", default: "local", null: false, comment: "保存場所 (local, s3, gcs)"
    t.bigint "file_size", comment: "ファイルサイズ（バイト）"
    t.string "file_hash", comment: "ファイルハッシュ値（整合性確認用）"
    t.bigint "admin_id", null: false, comment: "生成実行者"
    t.json "generation_metadata", comment: "生成時のメタデータ（実行時間、パラメータ等）"
    t.datetime "generated_at", null: false, comment: "ファイル生成日時"
    t.integer "download_count", default: 0, comment: "ダウンロード回数"
    t.datetime "last_accessed_at", comment: "最終アクセス日時"
    t.integer "email_delivery_count", default: 0, comment: "メール配信回数"
    t.datetime "last_delivered_at", comment: "最終配信日時"
    t.string "retention_policy", default: "standard", comment: "保持ポリシー (standard, extended, permanent)"
    t.date "expires_at", comment: "保持期限日"
    t.string "status", default: "active", comment: "ファイル状態 (active, archived, deleted)"
    t.datetime "archived_at", comment: "アーカイブ日時"
    t.datetime "deleted_at", comment: "削除日時"
    t.string "checksum_algorithm", default: "sha256", comment: "チェックサム算出アルゴリズム"
    t.text "notes", comment: "管理者メモ"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "idx_report_files_admin_id"
    t.index ["admin_id"], name: "index_report_files_on_admin_id"
    t.index ["file_format", "status"], name: "idx_report_files_format_status"
    t.index ["generated_at"], name: "idx_report_files_generated_at"
    t.index ["last_accessed_at"], name: "idx_report_files_last_access"
    t.index ["report_type", "file_format", "report_period", "status"], name: "idx_report_files_unique_active", unique: true
    t.index ["report_type", "report_period"], name: "idx_report_files_type_period"
    t.index ["status", "expires_at"], name: "idx_report_files_cleanup"
  end

  create_table "shipments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "inventory_id", null: false
    t.integer "quantity"
    t.string "destination"
    t.date "scheduled_date"
    t.integer "shipment_status"
    t.string "tracking_number"
    t.string "carrier"
    t.text "notes"
    t.integer "return_quantity"
    t.string "return_reason"
    t.date "return_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id"], name: "index_shipments_on_inventory_id"
  end

  create_table "store_inventories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "store_id", null: false, comment: "店舗ID"
    t.bigint "inventory_id", null: false, comment: "商品ID"
    t.integer "quantity", default: 0, null: false, comment: "現在在庫数"
    t.integer "reserved_quantity", default: 0, null: false, comment: "予約済み在庫数（移動申請中等）"
    t.integer "safety_stock_level", default: 5, null: false, comment: "安全在庫レベル（アラート閾値）"
    t.datetime "last_updated_at", comment: "最終在庫更新日時"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["inventory_id"], name: "index_store_inventories_on_inventory_id"
    t.index ["last_updated_at"], name: "index_store_inventories_on_last_updated_at", comment: "最終更新日時検索最適化"
    t.index ["quantity", "safety_stock_level"], name: "idx_stock_levels", comment: "在庫レベル検索最適化"
    t.index ["store_id", "inventory_id"], name: "uniq_store_inventory", unique: true, comment: "店舗・商品組み合わせ一意制約"
    t.index ["store_id", "quantity", "safety_stock_level"], name: "idx_low_stock_alert", comment: "低在庫アラート検索最適化"
    t.index ["store_id"], name: "index_store_inventories_on_store_id"
  end

  create_table "store_users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.string "email", null: false
    t.string "encrypted_password", null: false
    t.string "role", default: "staff", null: false
    t.boolean "active", default: true, null: false
    t.datetime "last_sign_in_at"
    t.datetime "current_sign_in_at"
    t.string "last_sign_in_ip"
    t.string "current_sign_in_ip"
    t.integer "sign_in_count", default: 0, null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.string "unlock_token"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name", null: false
    t.string "employee_code"
    t.datetime "password_changed_at"
    t.boolean "must_change_password", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_store_users_on_active"
    t.index ["email"], name: "index_store_users_on_email"
    t.index ["reset_password_token"], name: "index_store_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_store_users_on_role"
    t.index ["store_id", "email"], name: "index_store_users_on_store_id_and_email", unique: true
    t.index ["store_id", "employee_code"], name: "index_store_users_on_store_id_and_employee_code", unique: true
    t.index ["store_id"], name: "index_store_users_on_store_id"
    t.index ["unlock_token"], name: "index_store_users_on_unlock_token", unique: true
  end

  create_table "stores", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", limit: 100, null: false, comment: "店舗名"
    t.string "code", limit: 20, null: false, comment: "店舗コード（一意識別子）"
    t.string "store_type", limit: 30, default: "pharmacy", null: false, comment: "店舗種別（pharmacy, warehouse, headquarters）"
    t.string "region", limit: 50, comment: "地域・エリア"
    t.text "address", comment: "住所"
    t.string "phone", limit: 20, comment: "電話番号"
    t.string "email", limit: 100, comment: "店舗メールアドレス"
    t.string "manager_name", limit: 50, comment: "店舗責任者名"
    t.boolean "active", default: true, null: false, comment: "店舗有効フラグ"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "store_inventories_count", default: 0, null: false
    t.integer "pending_outgoing_transfers_count", default: 0, null: false
    t.integer "pending_incoming_transfers_count", default: 0, null: false
    t.integer "low_stock_items_count", default: 0, null: false
    t.string "slug", null: false
    t.index ["active"], name: "index_stores_on_active", comment: "有効店舗フィルタ最適化"
    t.index ["code"], name: "index_stores_on_code", unique: true, comment: "店舗コード一意制約"
    t.index ["low_stock_items_count"], name: "index_stores_on_low_stock_items_count"
    t.index ["region"], name: "index_stores_on_region", comment: "地域別検索最適化"
    t.index ["slug"], name: "index_stores_on_slug", unique: true
    t.index ["store_inventories_count"], name: "index_stores_on_store_inventories_count"
    t.index ["store_type", "active"], name: "index_stores_on_store_type_and_active", comment: "種別・有効状態複合検索"
    t.index ["store_type"], name: "index_stores_on_store_type", comment: "店舗種別による検索最適化"
  end

  add_foreign_key "admin_notification_settings", "admins"
  add_foreign_key "admins", "stores"
  add_foreign_key "audit_logs", "admins", column: "user_id", on_delete: :nullify
  add_foreign_key "batches", "inventories", on_delete: :cascade
  add_foreign_key "identities", "admins"
  add_foreign_key "inter_store_transfers", "admins", column: "approved_by_id"
  add_foreign_key "inter_store_transfers", "admins", column: "requested_by_id"
  add_foreign_key "inter_store_transfers", "inventories", on_delete: :cascade
  add_foreign_key "inter_store_transfers", "stores", column: "destination_store_id", on_delete: :cascade
  add_foreign_key "inter_store_transfers", "stores", column: "source_store_id", on_delete: :cascade
  add_foreign_key "inventory_logs", "inventories"
  add_foreign_key "receipts", "inventories"
  add_foreign_key "report_files", "admins"
  add_foreign_key "shipments", "inventories"
  add_foreign_key "store_inventories", "inventories", on_delete: :cascade
  add_foreign_key "store_inventories", "stores", on_delete: :cascade
  add_foreign_key "store_users", "stores"
end
