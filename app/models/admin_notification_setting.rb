# frozen_string_literal: true

# ============================================
# Admin Notification Setting Model
# ============================================
# 管理者の個別通知設定管理
# REF: doc/remaining_tasks.md - 通知設定のカスタマイズ（優先度：中）

class AdminNotificationSetting < ApplicationRecord
  # ============================================
  # 関連・バリデーション
  # ============================================

  belongs_to :admin

  # 通知タイプの定義（Rails 8対応：位置引数使用）
  enum :notification_type, {
    csv_import: "csv_import",
    stock_alert: "stock_alert",
    security_alert: "security_alert",
    system_maintenance: "system_maintenance",
    monthly_report: "monthly_report",
    error_notification: "error_notification"
  }

  # 通知方法の定義
  enum :delivery_method, {
    email: "email",
    actioncable: "actioncable",
    slack: "slack",
    teams: "teams",
    webhook: "webhook"
  }

  # 優先度の定義
  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    critical: 3
  }

  # バリデーション
  validates :notification_type, presence: true
  validates :delivery_method, presence: true
  validates :enabled, inclusion: { in: [ true, false ] }
  validates :frequency_minutes, numericality: {
    greater_than: 0,
    less_than_or_equal_to: 1440  # 最大24時間
  }, allow_nil: true

  validates :admin_id, uniqueness: {
    scope: [ :notification_type, :delivery_method ],
    message: "同じ通知タイプと配信方法の組み合わせは既に存在します"
  }

  # ============================================
  # スコープ
  # ============================================

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :by_type, ->(type) { where(notification_type: type) }
  scope :by_method, ->(method) { where(delivery_method: method) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :critical_only, -> { where(priority: :critical) }
  scope :high_priority_and_above, -> { where(priority: [ :high, :critical ]) }

  # ============================================
  # インスタンスメソッド
  # ============================================

  # 通知送信が可能かチェック
  def can_send_notification?
    return false unless enabled?
    return true unless frequency_minutes.present?

    # 頻度制限のチェック
    last_sent = last_sent_at || Time.at(0)
    Time.current >= last_sent + frequency_minutes.minutes
  end

  # 通知送信後の更新
  def mark_as_sent!
    update!(
      last_sent_at: Time.current,
      sent_count: (sent_count || 0) + 1
    )
  end

  # 設定の概要文字列
  def summary
    status = enabled? ? "有効" : "無効"
    freq = frequency_minutes.present? ? "#{frequency_minutes}分間隔" : "制限なし"
    "#{notification_type_label} - #{delivery_method_label} (#{status}, #{freq})"
  end

  # 通知タイプの日本語ラベル
  def notification_type_label
    case notification_type
    when "csv_import" then "CSV\u30A4\u30F3\u30DD\u30FC\u30C8"
    when "stock_alert" then "\u5728\u5EAB\u30A2\u30E9\u30FC\u30C8"
    when "security_alert" then "\u30BB\u30AD\u30E5\u30EA\u30C6\u30A3\u30A2\u30E9\u30FC\u30C8"
    when "system_maintenance" then "\u30B7\u30B9\u30C6\u30E0\u30E1\u30F3\u30C6\u30CA\u30F3\u30B9"
    when "monthly_report" then "\u6708\u6B21\u30EC\u30DD\u30FC\u30C8"
    when "error_notification" then "\u30A8\u30E9\u30FC\u901A\u77E5"
    else notification_type
    end
  end

  # 配信方法の日本語ラベル
  def delivery_method_label
    case delivery_method
    when "email" then "\u30E1\u30FC\u30EB"
    when "actioncable" then "\u30EA\u30A2\u30EB\u30BF\u30A4\u30E0\u901A\u77E5"
    when "slack" then "Slack"
    when "teams" then "Microsoft Teams"
    when "webhook" then "Webhook"
    else delivery_method
    end
  end

  # 優先度の日本語ラベル
  def priority_label
    case priority
    when "low" then "\u4F4E"
    when "medium" then "\u4E2D"
    when "high" then "\u9AD8"
    when "critical" then "\u7DCA\u6025"
    else priority
    end
  end

  # 設定が有効期間内かチェック
  def within_active_period?
    return true unless active_from.present? || active_until.present?

    current_time = Time.current
    return false if active_from.present? && current_time < active_from
    return false if active_until.present? && current_time > active_until

    true
  end

  # ============================================
  # クラスメソッド
  # ============================================

  class << self
    # 管理者のデフォルト設定を作成
    def create_default_settings_for(admin)
      default_configs = [
        {
          notification_type: "csv_import",
          delivery_method: "actioncable",
          enabled: true,
          priority: "medium"
        },
        {
          notification_type: "csv_import",
          delivery_method: "email",
          enabled: false,
          priority: "medium"
        },
        {
          notification_type: "stock_alert",
          delivery_method: "actioncable",
          enabled: true,
          priority: "high"
        },
        {
          notification_type: "security_alert",
          delivery_method: "actioncable",
          enabled: true,
          priority: "critical"
        },
        {
          notification_type: "security_alert",
          delivery_method: "email",
          enabled: true,
          priority: "critical",
          frequency_minutes: 5  # 5分間隔制限
        },
        {
          notification_type: "system_maintenance",
          delivery_method: "email",
          enabled: true,
          priority: "high"
        },
        {
          notification_type: "monthly_report",
          delivery_method: "email",
          enabled: true,
          priority: "low"
        },
        {
          notification_type: "error_notification",
          delivery_method: "actioncable",
          enabled: true,
          priority: "high"
        }
      ]

      transaction do
        default_configs.each do |config|
          admin.admin_notification_settings.find_or_create_by(
            notification_type: config[:notification_type],
            delivery_method: config[:delivery_method]
          ) do |setting|
            setting.assign_attributes(config)
          end
        end
      end
    end

    # 特定の通知タイプで有効な管理者を取得
    def admins_for_notification(notification_type, delivery_method = nil, min_priority = :low)
      query = joins(:admin)
              .enabled
              .by_type(notification_type)
              .where(priority: priority_levels_from(min_priority))

      query = query.by_method(delivery_method) if delivery_method.present?

      # 頻度制限と有効期間をチェック
      query.select(&:can_send_notification?)
           .select(&:within_active_period?)
           .map(&:admin)
           .uniq
    end

    # 一括設定更新
    def bulk_update_settings(admin, settings_params)
      transaction do
        settings_params.each do |setting_params|
          setting = admin.admin_notification_settings
                         .find_or_initialize_by(
                           notification_type: setting_params[:notification_type],
                           delivery_method: setting_params[:delivery_method]
                         )
          setting.update!(setting_params.except(:notification_type, :delivery_method))
        end
      end
    end

    # 統計情報の取得
    def notification_statistics(period = 30.days)
      start_date = period.ago

      {
        total_settings: count,
        enabled_settings: enabled.count,
        by_type: group(:notification_type).count,
        by_method: group(:delivery_method).count,
        by_priority: group(:priority).count,
        recent_activity: where("last_sent_at >= ?", start_date)
                        .group(:notification_type)
                        .sum(:sent_count)
      }
    end

    private

    def priority_levels_from(min_priority)
      priority_index = priorities[min_priority.to_s]
      return priorities.keys if priority_index.nil?

      priorities.select { |_, index| index >= priority_index }.keys
    end
  end

  # ============================================
  # コールバック
  # ============================================

  before_validation :set_defaults, on: :create
  after_create :log_setting_created
  after_update :log_setting_updated

  private

  def set_defaults
    self.priority ||= :medium
    self.enabled = true if enabled.nil?
    self.sent_count ||= 0
  end

  def log_setting_created
    Rails.logger.info({
      event: "notification_setting_created",
      admin_id: admin_id,
      notification_type: notification_type,
      delivery_method: delivery_method,
      enabled: enabled
    }.to_json)
  end

  def log_setting_updated
    if saved_change_to_enabled?
      action = enabled? ? "enabled" : "disabled"
      Rails.logger.info({
        event: "notification_setting_#{action}",
        admin_id: admin_id,
        notification_type: notification_type,
        delivery_method: delivery_method
      }.to_json)
    end
  end
end

# ============================================
# TODO: 通知設定システムの拡張計画（優先度：中）
# REF: doc/remaining_tasks.md - 通知設定のカスタマイズ
# ============================================
# 1. 高度なスケジューリング機能（優先度：中）
#    - 曜日・時間帯指定での通知制御
#    - 祝日・営業日カレンダー連携
#    - タイムゾーン対応
#
# 2. 通知テンプレート機能（優先度：中）
#    - カスタム通知メッセージテンプレート
#    - 言語・地域別テンプレート
#    - 動的コンテンツ挿入
#
# 3. エスカレーション機能（優先度：高）
#    - 未読通知の自動エスカレーション
#    - 上位管理者への自動転送
#    - 緊急時の即座通知機能
#
# 4. 分析・改善機能（優先度：低）
#    - 通知効果測定（開封率、反応率）
#    - 最適な通知頻度の提案
#    - 通知疲れの検出と軽減
#
# 5. 外部システム連携（優先度：中）
#    - Microsoft Teams 連携強化
#    - Discord, LINE 等の追加対応
#    - SMS 通知機能
#    - Push 通知対応（PWA）
