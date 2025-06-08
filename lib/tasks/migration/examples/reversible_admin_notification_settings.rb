# frozen_string_literal: true

require_relative "../load_controlled_migration"

# ReversibleAdminNotificationSettings - AdminNotificationSettings作成の可逆マイグレーション例
#
# 既存のマイグレーションを可逆化し、負荷制御も適用した実装例
# これはdb/migrate/20250523074600_create_admin_notification_settings.rbの改善版
class ReversibleAdminNotificationSettings < LoadControlledMigration
  # 実行前の状態を記録
  def initialize(*)
    super
    @table_name = :admin_notification_settings
    @created_table = false
    @created_indexes = []
    @created_records = []
  end

  protected

  # メインのマイグレーション処理
  def execute_with_rollback_support
    Rails.logger.info "Creating admin notification settings table with full reversibility..."

    # 1. テーブル作成
    create_notification_settings_table

    # 2. インデックス作成
    create_indexes_with_monitoring

    # 3. 初期データ作成（負荷制御付き）
    create_default_settings_for_existing_admins

    # 4. データ整合性検証
    verify_data_integrity
  end

  # カスタム整合性チェック
  def run_custom_validations
    # 外部キー制約の確認
    unless foreign_key_exists?(:admin_notification_settings, :admins)
      raise "Foreign key constraint to admins table is missing"
    end

    # 一意制約の確認
    unless index_exists?(:admin_notification_settings, [ :admin_id, :notification_type, :delivery_method ], unique: true)
      raise "Unique constraint is missing"
    end

    # データの妥当性確認
    invalid_count = AdminNotificationSetting.where.not(priority: 0..3).count
    if invalid_count > 0
      raise "Found #{invalid_count} records with invalid priority values"
    end
  end

  private

  # ============================================
  # テーブル作成（可逆）
  # ============================================

  def create_notification_settings_table
    unless table_exists?(@table_name)
      create_table @table_name do |t|
        # 管理者への外部キー
        t.references :admin, null: false, foreign_key: true, index: true

        # 通知設定の基本情報
        t.string :notification_type, null: false, comment: "通知タイプ（csv_import, stock_alert等）"
        t.string :delivery_method, null: false, comment: "配信方法（email, actioncable等）"
        t.boolean :enabled, null: false, default: true, comment: "通知の有効/無効"

        # 優先度と頻度制御
        t.integer :priority, null: false, default: 1, comment: "優先度（0:低 1:中 2:高 3:緊急）"
        t.integer :frequency_minutes, null: true, comment: "通知頻度制限（分）"

        # 通知履歴・統計
        t.datetime :last_sent_at, null: true, comment: "最後の通知送信日時"
        t.integer :sent_count, null: false, default: 0, comment: "送信回数"

        # 有効期間設定
        t.datetime :active_from, null: true, comment: "有効期間開始日時"
        t.datetime :active_until, null: true, comment: "有効期間終了日時"

        # 設定詳細（JSON形式）
        t.text :settings_json, null: true, comment: "詳細設定（JSON形式）"

        # 作成・更新日時
        t.timestamps null: false
      end

      @created_table = true
      Rails.logger.info "Created table: #{@table_name}"

      # ロールバックデータを記録
      @rollback_data << {
        operation: :created_table,
        table_name: @table_name,
        timestamp: Time.current
      }
    end
  end

  # ============================================
  # インデックス作成（監視付き）
  # ============================================

  def create_indexes_with_monitoring
    indexes_to_create = [
      {
        columns: [ :admin_id, :notification_type, :delivery_method ],
        options: { unique: true, name: "idx_admin_notification_unique" }
      },
      {
        columns: :notification_type,
        options: {}
      },
      {
        columns: :delivery_method,
        options: {}
      },
      {
        columns: :enabled,
        options: {}
      },
      {
        columns: :priority,
        options: {}
      },
      {
        columns: :last_sent_at,
        options: {}
      },
      {
        columns: [ :notification_type, :enabled ],
        options: { name: "idx_notification_type_enabled" }
      },
      {
        columns: [ :delivery_method, :enabled ],
        options: { name: "idx_delivery_method_enabled" }
      },
      {
        columns: [ :priority, :enabled ],
        options: { name: "idx_priority_enabled" }
      }
    ]

    indexes_to_create.each do |index_spec|
      create_index_with_monitoring(index_spec[:columns], index_spec[:options])
    end
  end

  def create_index_with_monitoring(columns, options = {})
    index_name = options[:name] || index_name(@table_name, columns)

    unless index_exists?(@table_name, columns, options)
      Rails.logger.info "Creating index: #{index_name}"
      start_time = Time.current

      add_index @table_name, columns, **options

      execution_time = Time.current - start_time
      Rails.logger.info "Created index #{index_name} in #{execution_time.round(2)}s"

      # インデックス作成の記録
      @created_indexes << {
        table: @table_name,
        columns: columns,
        options: options,
        name: index_name
      }

      # ロールバックデータを記録
      @rollback_data << {
        operation: :created_index,
        table_name: @table_name,
        index_name: index_name,
        timestamp: Time.current
      }
    end
  end

  # ============================================
  # 初期データ作成（負荷制御付き）
  # ============================================

  def create_default_settings_for_existing_admins
    return unless table_exists?(:admins) && Admin.exists?

    # 監視開始
    monitor_key = MigrationMonitor.start_monitoring(
      "create_default_notification_settings",
      total_records: Admin.count * default_notification_types.size
    )

    total_created = 0

    # 管理者ごとにデフォルト設定を作成
    Admin.find_in_batches(batch_size: @current_batch_size) do |admin_batch|
      batch_start = Time.current

      admin_batch.each do |admin|
        created_count = create_default_settings_for_admin(admin)
        total_created += created_count

        # 進捗更新
        MigrationMonitor.update_progress(monitor_key, total_created)
      end

      batch_time = Time.current - batch_start

      # パフォーマンスメトリクスを記録
      MigrationMonitor.update_progress(
        monitor_key,
        total_created,
        metrics: {
          batch_size: admin_batch.size,
          execution_time: batch_time,
          records_per_second: (admin_batch.size * default_notification_types.size / batch_time).round(2)
        }
      )

      # 動的負荷制御
      apply_dynamic_load_control
    end

    # 監視終了
    MigrationMonitor.stop_monitoring(monitor_key)

    Rails.logger.info "Created #{total_created} default notification settings"
  end

  def create_default_settings_for_admin(admin)
    created_count = 0

    default_notification_types.each do |type_config|
      begin
        setting = AdminNotificationSetting.create!(
          admin: admin,
          notification_type: type_config[:type],
          delivery_method: type_config[:method],
          enabled: type_config[:enabled],
          priority: type_config[:priority],
          settings_json: type_config[:settings].to_json
        )

        @created_records << setting.id
        created_count += 1
      rescue ActiveRecord::RecordNotUnique
        # 既に存在する場合はスキップ
        Rails.logger.debug "Notification setting already exists for admin #{admin.id}, type: #{type_config[:type]}"
      end
    end

    # ロールバックデータを記録（バッチごと）
    if created_count > 0
      @rollback_data << {
        operation: :created_records,
        model_class: "AdminNotificationSetting",
        ids: @created_records.last(created_count),
        timestamp: Time.current
      }
    end

    created_count
  end

  # デフォルト通知タイプの定義
  def default_notification_types
    [
      {
        type: "csv_import_completed",
        method: "email",
        enabled: true,
        priority: 1,
        settings: {
          subject_prefix: "[StockRx]",
          include_summary: true
        }
      },
      {
        type: "csv_import_failed",
        method: "email",
        enabled: true,
        priority: 2,
        settings: {
          subject_prefix: "[StockRx ERROR]",
          include_error_details: true
        }
      },
      {
        type: "stock_alert",
        method: "email",
        enabled: true,
        priority: 2,
        settings: {
          threshold_percentage: 20,
          frequency_minutes: 60
        }
      },
      {
        type: "system_alert",
        method: "email",
        enabled: true,
        priority: 3,
        settings: {
          alert_types: [ "critical", "security" ]
        }
      }
    ]
  end

  # ============================================
  # カスタムロールバック処理
  # ============================================

  def execute_rollback
    super # 親クラスの標準ロールバックを実行

    # テーブル削除は最後に実行
    if @created_table
      drop_table @table_name, if_exists: true
      Rails.logger.info "Dropped table: #{@table_name}"
    end
  end
end

# 実行例:
# rails generate migration ReversibleAdminNotificationSettings
# 生成されたファイルの内容をこのクラスで置き換える
