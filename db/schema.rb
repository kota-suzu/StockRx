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

ActiveRecord::Schema[8.0].define(version: 2025_06_08_090912) do
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
    t.index ["email"], name: "index_admins_on_email", unique: true
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

  create_table "inventories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.integer "quantity", default: 0, null: false
    t.decimal "price", precision: 10, scale: 2, default: "0.0", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "batch_tracking_enabled"
    t.boolean "batch_number_required"
    t.boolean "expiry_date_required"
    t.index ["name"], name: "index_inventories_on_name"
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

  create_table "migration_executions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "version", null: false, comment: "マイグレーションバージョン（タイムスタンプ）"
    t.string "name", null: false, comment: "マイグレーション名"
    t.string "status", default: "pending", null: false, comment: "pending/running/completed/failed/rolled_back"
    t.bigint "admin_id", null: false, comment: "実行者"
    t.datetime "started_at", comment: "実行開始日時"
    t.datetime "completed_at", comment: "実行完了日時"
    t.bigint "processed_records", default: 0, comment: "処理済みレコード数"
    t.bigint "total_records", default: 0, comment: "総レコード数"
    t.decimal "progress_percentage", precision: 5, scale: 2, default: "0.0", comment: "進行率（%）"
    t.json "configuration", comment: "実行時設定（バッチサイズ、閾値等）"
    t.json "rollback_data", comment: "ロールバック用データ"
    t.json "metrics", comment: "パフォーマンスメトリクス（CPU、メモリ等）"
    t.text "error_message", comment: "エラーメッセージ"
    t.text "error_backtrace", comment: "エラーバックトレース"
    t.integer "retry_count", default: 0, comment: "リトライ回数"
    t.string "environment", default: "development", comment: "実行環境"
    t.string "hostname", comment: "実行ホスト名"
    t.integer "process_id", comment: "プロセスID"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id", "created_at"], name: "idx_migration_executions_admin_created"
    t.index ["admin_id"], name: "index_migration_executions_on_admin_id"
    t.index ["completed_at"], name: "idx_migration_executions_completed"
    t.index ["environment"], name: "idx_migration_executions_environment"
    t.index ["progress_percentage"], name: "idx_migration_executions_progress"
    t.index ["started_at"], name: "idx_migration_executions_started"
    t.index ["status", "created_at"], name: "idx_migration_executions_status_created"
    t.index ["status"], name: "idx_migration_executions_status"
    t.index ["version"], name: "idx_migration_executions_version", unique: true
  end

  create_table "migration_progress_logs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "migration_execution_id", null: false, comment: "マイグレーション実行ID"
    t.string "phase", null: false, comment: "実行フェーズ"
    t.decimal "progress_percentage", precision: 5, scale: 2, default: "0.0", null: false, comment: "進行率（%）"
    t.bigint "processed_records", default: 0, comment: "処理済みレコード数"
    t.integer "current_batch_size", comment: "現在のバッチサイズ"
    t.integer "current_batch_number", comment: "現在のバッチ番号"
    t.text "message", comment: "ログメッセージ"
    t.string "log_level", default: "info", comment: "ログレベル"
    t.json "metrics", comment: "システムメトリクス"
    t.decimal "records_per_second", precision: 10, scale: 2, comment: "レコード処理速度（/秒）"
    t.decimal "estimated_remaining_seconds", precision: 10, scale: 2, comment: "推定残り時間（秒）"
    t.boolean "broadcasted", default: false, comment: "ActionCableブロードキャスト済み"
    t.datetime "broadcasted_at", comment: "ブロードキャスト日時"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["broadcasted", "created_at"], name: "idx_progress_logs_broadcast_time"
    t.index ["log_level"], name: "idx_progress_logs_level"
    t.index ["migration_execution_id", "created_at"], name: "idx_progress_logs_execution_time"
    t.index ["migration_execution_id", "phase"], name: "idx_progress_logs_execution_phase"
    t.index ["migration_execution_id"], name: "index_migration_progress_logs_on_migration_execution_id"
    t.index ["records_per_second"], name: "idx_progress_logs_performance"
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

  create_table "reversible_admin_notification_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
  add_foreign_key "inventory_logs", "inventories"
  add_foreign_key "migration_executions", "admins"
  add_foreign_key "migration_progress_logs", "migration_executions"
  add_foreign_key "receipts", "inventories"
  add_foreign_key "shipments", "inventories"
end
