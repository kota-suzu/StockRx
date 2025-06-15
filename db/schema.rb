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

ActiveRecord::Schema[8.0].define(version: 2025_06_15_000257) do
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
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["provider", "uid"], name: "index_admins_on_provider_and_uid", unique: true
    t.index ["provider"], name: "index_admins_on_provider"
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
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
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable"
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
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

  add_foreign_key "admin_notification_settings", "admins"
  add_foreign_key "audit_logs", "admins", column: "user_id", on_delete: :nullify
  add_foreign_key "batches", "inventories", on_delete: :cascade
  add_foreign_key "identities", "admins"
  add_foreign_key "inventory_logs", "inventories"
  add_foreign_key "receipts", "inventories"
  add_foreign_key "report_files", "admins"
  add_foreign_key "shipments", "inventories"
end
