# frozen_string_literal: true

class CreateAdminNotificationSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :admin_notification_settings do |t|
      # 管理者への外部キー
      t.references :admin, null: false, foreign_key: true, index: true

      # 通知設定の基本情報
      t.string :notification_type, null: false, comment: '通知タイプ（csv_import, stock_alert等）'
      t.string :delivery_method, null: false, comment: '配信方法（email, actioncable等）'
      t.boolean :enabled, null: false, default: true, comment: '通知の有効/無効'

      # 優先度と頻度制御
      t.integer :priority, null: false, default: 1, comment: '優先度（0:低 1:中 2:高 3:緊急）'
      t.integer :frequency_minutes, null: true, comment: '通知頻度制限（分）'

      # 通知履歴・統計
      t.datetime :last_sent_at, null: true, comment: '最後の通知送信日時'
      t.integer :sent_count, null: false, default: 0, comment: '送信回数'

      # 有効期間設定
      t.datetime :active_from, null: true, comment: '有効期間開始日時'
      t.datetime :active_until, null: true, comment: '有効期間終了日時'

      # 設定詳細（JSON形式）
      t.text :settings_json, null: true, comment: '詳細設定（JSON形式）'

      # 作成・更新日時
      t.timestamps null: false
    end

    # ============================================
    # インデックス
    # ============================================

    # 複合一意制約：同じ管理者・通知タイプ・配信方法の組み合わせは一意
    add_index :admin_notification_settings,
              [ :admin_id, :notification_type, :delivery_method ],
              unique: true,
              name: 'idx_admin_notification_unique'

    # パフォーマンス用インデックス
    add_index :admin_notification_settings, :notification_type
    add_index :admin_notification_settings, :delivery_method
    add_index :admin_notification_settings, :enabled
    add_index :admin_notification_settings, :priority
    add_index :admin_notification_settings, :last_sent_at

    # 複合インデックス（よく使われるクエリ用）
    add_index :admin_notification_settings,
              [ :notification_type, :enabled ],
              name: 'idx_notification_type_enabled'

    add_index :admin_notification_settings,
              [ :delivery_method, :enabled ],
              name: 'idx_delivery_method_enabled'

    add_index :admin_notification_settings,
              [ :priority, :enabled ],
              name: 'idx_priority_enabled'

    # ============================================
    # 初期データの挿入
    # ============================================

    # 管理者が既に存在する場合、デフォルト設定を作成
    reversible do |dir|
      dir.up do
        # マイグレーション実行時にAdminが存在するかチェック
        if table_exists?(:admins) && Admin.exists?
          Admin.find_each do |admin|
            AdminNotificationSetting.create_default_settings_for(admin)
          end

          Rails.logger.info "Created default notification settings for #{Admin.count} admins"
        end
      end
    end
  end
end

# ============================================
# 設計ノート
# ============================================
# 1. パフォーマンス考慮事項
#    - 頻繁にアクセスされるカラム（enabled, notification_type等）には個別インデックス
#    - よく組み合わせて検索されるカラムには複合インデックス
#    - 一意制約は複合インデックスで効率的に実装
#
# 2. 拡張性考慮事項
#    - settings_json カラムで将来的な設定項目追加に対応
#    - priority は integer で段階的な優先度設定が可能
#    - active_from/active_until で時限的な通知設定が可能
#
# 3. データ整合性
#    - NOT NULL 制約で必須項目を明確化
#    - DEFAULT 値で安全なデフォルト動作を保証
#    - 外部キー制約でデータ整合性を維持
#
# 4. 保守性
#    - コメント付きでカラムの用途を明確化
#    - 命名規則は Rails 標準に準拠
#    - マイグレーション内で初期データ作成も実行
