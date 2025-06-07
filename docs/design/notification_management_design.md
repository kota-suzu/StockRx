# 通知管理オブジェクト設計書 - 在庫アラート機能の拡張

## 1. 概要

### 1.1 現状と課題

StockRxの通知システムは既に充実した基盤を持っているが、在庫アラート機能において以下の課題が存在する：

#### 現状の強み
- `AdminNotificationSetting`による柔軟な通知設定
- マルチチャネル配信（Email、ActionCable、Slack等）
- 優先度とレート制限機能
- リアルタイム通知基盤（ActionCable）

#### 主要な課題
1. **統合不足**: StockAlertJobがAdminNotificationSettingを使用していない
2. **画一的な閾値**: 商品カテゴリを問わず固定閾値（10個）
3. **限定的なアラート条件**: 数量ベースのみで、消費パターンを考慮しない
4. **テンプレート不足**: 在庫アラートのメールテンプレートが未実装
5. **エスカレーション機能なし**: 重要度に応じた段階的通知がない

### 1.2 目的

本設計書では、以下を実現する拡張された通知管理システムを提案する：

- 既存のAdminNotificationSettingとの完全統合
- 動的な閾値設定とカテゴリ別管理
- 予測的アラート機能
- マルチレベルエスカレーション
- カスタマイズ可能な通知テンプレート

## 2. 設計方針

### 2.1 基本原則

1. **既存アーキテクチャの活用**: AdminNotificationSettingを中核とした設計
2. **段階的拡張**: 現在のStockAlertJobを破壊的変更なく改善
3. **設定駆動**: ConfigurationServiceとの連携でビジネスルール外部化
4. **予測性**: 消費傾向に基づくプロアクティブアラート
5. **スケーラビリティ**: 大量商品への対応

### 2.2 スコープ

#### 対象機能
- 在庫レベル別アラート（在庫切れ、低在庫、危険在庫）
- 予測アラート（予想在庫切れ日）
- カテゴリ別閾値管理
- エスカレーション通知
- バッチ通知とサマリー配信

#### 対象外
- 有効期限アラート（既存のExpiryCheckJobが担当）
- セキュリティ通知（別途設計）
- システムメンテナンス通知（現状維持）

## 3. アーキテクチャ設計

### 3.1 全体構成

```
┌─────────────────────────────────────────────────────┐
│                Notification Triggers               │
│   (Cron Jobs, Manual Triggers, Event-based)        │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│            NotificationOrchestrator                 │
│         (通知の調整と配信管理)                        │
└─────────┬───────────────────────┬───────────────────┘
          │                       │
┌─────────▼──────────┐    ┌──────▼─────────────────────┐
│ InventoryAlert     │    │  NotificationTemplate      │
│   Manager          │    │     Manager                │
│ (アラート生成)      │    │  (テンプレート管理)         │
└─────────┬──────────┘    └────────────────────────────┘
          │
┌─────────▼──────────┐
│ NotificationSender │
│   (配信実行)        │
└─────────┬──────────┘
          │
┌─────────▼──────────┐
│   Delivery         │
│   Channels         │
│ (Email/Cable/Slack)│
└────────────────────┘
```

### 3.2 コアコンポーネント

#### 3.2.1 NotificationOrchestrator

```ruby
# app/services/notification_orchestrator.rb
class NotificationOrchestrator
  include Singleton

  def self.send_inventory_alerts(force: false)
    instance.send_inventory_alerts(force: force)
  end

  def send_inventory_alerts(force: false)
    # 1. アラート対象の在庫を特定
    alert_data = InventoryAlertManager.generate_alerts

    return if alert_data.empty? && !force

    # 2. 通知設定を取得し、配信対象者を決定
    recipients = determine_recipients(alert_data)

    # 3. 各受信者に対してパーソナライズされた通知を生成・配信
    recipients.each do |recipient_data|
      NotificationSender.send_alerts(recipient_data)
    end

    # 4. 配信結果をログに記録
    log_delivery_results(recipients)
  end

  private

  def determine_recipients(alert_data)
    NotificationRecipientResolver.new(alert_data).resolve
  end

  def log_delivery_results(recipients)
    NotificationDeliveryLog.bulk_create(recipients)
  end
end
```

#### 3.2.2 InventoryAlertManager

```ruby
# app/services/inventory_alert_manager.rb
class InventoryAlertManager
  # アラートタイプの定義
  ALERT_TYPES = {
    out_of_stock: 'critical',
    critical_low: 'high', 
    low_stock: 'medium',
    predicted_stockout: 'medium',
    category_threshold: 'low'
  }.freeze

  def self.generate_alerts
    new.generate_alerts
  end

  def generate_alerts
    {
      out_of_stock: find_out_of_stock_items,
      critical_low: find_critical_low_items,
      low_stock: find_low_stock_items,
      predicted_stockout: find_predicted_stockout_items,
      category_alerts: find_category_specific_alerts
    }.compact_blank
  end

  private

  def find_out_of_stock_items
    Inventory.out_of_stock
             .includes(:batches, :category)
             .map { |item| build_alert_data(item, :out_of_stock) }
  end

  def find_critical_low_items
    threshold = dynamic_threshold(:critical)
    Inventory.where('quantity > 0 AND quantity <= ?', threshold)
             .includes(:batches, :category)
             .map { |item| build_alert_data(item, :critical_low) }
  end

  def find_low_stock_items
    low_threshold = dynamic_threshold(:low)
    critical_threshold = dynamic_threshold(:critical)
    
    Inventory.where('quantity > ? AND quantity <= ?', critical_threshold, low_threshold)
             .includes(:batches, :category)
             .map { |item| build_alert_data(item, :low_stock) }
  end

  def find_predicted_stockout_items
    return [] unless prediction_enabled?

    InventoryPredictionService.predict_stockouts(days_ahead: prediction_window)
                              .map { |prediction| build_prediction_alert(prediction) }
  end

  def build_alert_data(inventory, alert_type)
    {
      inventory: inventory,
      alert_type: alert_type,
      priority: ALERT_TYPES[alert_type],
      current_quantity: inventory.quantity,
      threshold: get_threshold_for(inventory, alert_type),
      category: inventory.category,
      last_updated: inventory.updated_at,
      predicted_stockout_date: prediction_enabled? ? 
        InventoryPredictionService.predict_stockout_date(inventory) : nil
    }
  end

  def dynamic_threshold(level)
    ConfigurationService.get("inventory.alert.#{level}_threshold", default: default_threshold(level))
  end

  def get_threshold_for(inventory, alert_type)
    # カテゴリ固有の閾値があれば使用、なければデフォルト
    category_key = "inventory.alert.category.#{inventory.category&.downcase}.#{alert_type}_threshold"
    ConfigurationService.get(category_key) || dynamic_threshold(alert_type.to_s.split('_').last)
  end
end
```

#### 3.2.3 NotificationRecipientResolver

```ruby
# app/services/notification_recipient_resolver.rb
class NotificationRecipientResolver
  def initialize(alert_data)
    @alert_data = alert_data
  end

  def resolve
    recipients = []

    @alert_data.each do |alert_type, items|
      next if items.empty?

      # アラートタイプと優先度に基づいて受信者を決定
      priority = InventoryAlertManager::ALERT_TYPES[alert_type]
      
      # 各配信方法について受信者を取得
      %w[email actioncable slack].each do |delivery_method|
        admins = AdminNotificationSetting.admins_for_notification(
          'stock_alert', 
          delivery_method, 
          priority
        )

        admins.each do |admin|
          recipients << {
            admin: admin,
            delivery_method: delivery_method,
            alert_type: alert_type,
            items: filter_items_for_admin(items, admin),
            priority: priority,
            template_data: build_template_data(alert_type, items, admin)
          }
        end
      end
    end

    # 重複排除とバッチング
    batch_and_deduplicate_recipients(recipients)
  end

  private

  def filter_items_for_admin(items, admin)
    # 管理者の担当カテゴリや権限に基づくフィルタリング
    # 将来的にはAdminCategoryAssignmentなどで実装
    items
  end

  def build_template_data(alert_type, items, admin)
    {
      alert_type: alert_type,
      item_count: items.size,
      items: items,
      admin: admin,
      generated_at: Time.current,
      dashboard_url: admin_dashboard_url,
      severity_level: InventoryAlertManager::ALERT_TYPES[alert_type]
    }
  end

  def batch_and_deduplicate_recipients(recipients)
    # 同一管理者・同一配信方法をバッチング
    recipients.group_by { |r| [r[:admin].id, r[:delivery_method]] }
              .map { |_key, group| merge_recipient_group(group) }
  end
end
```

#### 3.2.4 NotificationTemplateManager

```ruby
# app/services/notification_template_manager.rb
class NotificationTemplateManager
  TEMPLATE_TYPES = %w[email actioncable slack summary_email].freeze

  def self.render_template(template_type, template_data)
    new(template_type, template_data).render
  end

  def initialize(template_type, template_data)
    @template_type = template_type
    @template_data = template_data
    validate_template_type!
  end

  def render
    case @template_type
    when 'email'
      render_email_template
    when 'actioncable'
      render_actioncable_template
    when 'slack'
      render_slack_template
    when 'summary_email'
      render_summary_email_template
    end
  end

  private

  def render_email_template
    {
      subject: I18n.t('admin_mailer.stock_alert.subject', 
                     item_count: @template_data[:item_count],
                     severity: @template_data[:severity_level]),
      body: ApplicationController.render(
        template: 'admin_mailer/stock_alert',
        layout: 'mailer',
        assigns: @template_data
      ),
      priority: email_priority,
      headers: custom_email_headers
    }
  end

  def render_actioncable_template
    {
      type: 'stock_alert',
      data: {
        alert_type: @template_data[:alert_type],
        message: I18n.t("notifications.stock_alert.#{@template_data[:alert_type]}", 
                       count: @template_data[:item_count]),
        items: format_items_for_actioncable,
        severity: @template_data[:severity_level],
        timestamp: Time.current.iso8601,
        actions: available_actions
      }
    }
  end

  def render_slack_template
    {
      text: slack_message_text,
      attachments: [
        {
          color: severity_color,
          fields: slack_fields,
          actions: slack_actions,
          footer: "StockRx Alert System",
          ts: Time.current.to_i
        }
      ]
    }
  end
end
```

#### 3.2.5 NotificationSender

```ruby
# app/services/notification_sender.rb
class NotificationSender
  def self.send_alerts(recipient_data)
    new(recipient_data).send_alerts
  end

  def initialize(recipient_data)
    @recipient_data = recipient_data
  end

  def send_alerts
    # レート制限チェック
    return unless can_send_notification?

    template_content = NotificationTemplateManager.render_template(
      @recipient_data[:delivery_method],
      @recipient_data[:template_data]
    )

    delivery_result = case @recipient_data[:delivery_method]
    when 'email'
      send_email_notification(template_content)
    when 'actioncable'
      send_actioncable_notification(template_content)
    when 'slack'
      send_slack_notification(template_content)
    end

    # 送信結果の記録
    record_notification_sent(delivery_result)
    
    delivery_result
  rescue => e
    # エラーハンドリングとリトライ機構
    handle_notification_error(e)
  end

  private

  def can_send_notification?
    setting = AdminNotificationSetting.find_by(
      admin: @recipient_data[:admin],
      notification_type: 'stock_alert',
      delivery_method: @recipient_data[:delivery_method]
    )

    setting&.can_send_notification?
  end

  def send_email_notification(template_content)
    AdminMailer.stock_alert_enhanced(
      @recipient_data[:admin],
      @recipient_data[:template_data],
      template_content
    ).deliver_now

    { status: :delivered, delivered_at: Time.current }
  rescue => e
    { status: :failed, error: e.message, failed_at: Time.current }
  end

  def send_actioncable_notification(template_content)
    AdminChannel.broadcast_to(
      @recipient_data[:admin],
      template_content
    )

    { status: :delivered, delivered_at: Time.current }
  end

  def record_notification_sent(delivery_result)
    NotificationDeliveryLog.create!(
      admin: @recipient_data[:admin],
      notification_type: 'stock_alert',
      delivery_method: @recipient_data[:delivery_method],
      status: delivery_result[:status],
      delivered_at: delivery_result[:delivered_at],
      error_message: delivery_result[:error],
      alert_data: @recipient_data[:template_data]
    )

    # AdminNotificationSettingの送信カウンタ更新
    update_notification_setting_counters
  end
end
```

### 3.3 データモデル拡張

#### 3.3.1 NotificationDeliveryLog

```ruby
# app/models/notification_delivery_log.rb
class NotificationDeliveryLog < ApplicationRecord
  belongs_to :admin
  
  STATUSES = %w[delivered failed retrying].freeze
  NOTIFICATION_TYPES = %w[stock_alert csv_import expiry_alert security_alert].freeze
  DELIVERY_METHODS = %w[email actioncable slack teams webhook].freeze

  validates :notification_type, inclusion: { in: NOTIFICATION_TYPES }
  validates :delivery_method, inclusion: { in: DELIVERY_METHODS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: 'delivered') }
  scope :failed, -> { where(status: 'failed') }

  # 配信統計
  def self.delivery_stats(period = 7.days)
    where(created_at: period.ago..Time.current)
      .group(:notification_type, :delivery_method, :status)
      .count
  end
end
```

#### 3.3.2 InventoryCategory（新規）

```ruby
# app/models/inventory_category.rb
class InventoryCategory < ApplicationRecord
  has_many :inventories, foreign_key: :category_id
  has_many :category_alert_settings, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :priority_level, inclusion: { in: %w[low medium high critical] }

  # デフォルトのアラート閾値
  def alert_thresholds
    {
      critical: category_alert_settings.find_by(alert_type: 'critical')&.threshold || 
                ConfigurationService.get('inventory.alert.critical_threshold', default: 5),
      low: category_alert_settings.find_by(alert_type: 'low')&.threshold || 
           ConfigurationService.get('inventory.alert.low_threshold', default: 10)
    }
  end
end
```

#### 3.3.3 CategoryAlertSetting（新規）

```ruby
# app/models/category_alert_setting.rb
class CategoryAlertSetting < ApplicationRecord
  belongs_to :inventory_category

  ALERT_TYPES = %w[critical low predicted].freeze

  validates :alert_type, inclusion: { in: ALERT_TYPES }
  validates :threshold, presence: true, numericality: { greater_than: 0 }
  validates :alert_type, uniqueness: { scope: :inventory_category_id }

  # 設定の継承チェーン: Category → Global → Default
  def self.effective_threshold(category, alert_type)
    # 1. カテゴリ固有設定
    category_setting = find_by(inventory_category: category, alert_type: alert_type)
    return category_setting.threshold if category_setting

    # 2. グローバル設定
    global_threshold = ConfigurationService.get("inventory.alert.#{alert_type}_threshold")
    return global_threshold if global_threshold

    # 3. デフォルト値
    default_thresholds[alert_type.to_sym]
  end

  private

  def self.default_thresholds
    { critical: 5, low: 10, predicted: 15 }
  end
end
```

### 3.4 拡張されたStockAlertJob

```ruby
# app/jobs/enhanced_stock_alert_job.rb
class EnhancedStockAlertJob < ApplicationJob
  queue_as :default

  # 前のStockAlertJobとの互換性を保持
  def perform(threshold = nil, send_email = true)
    # 新しいオーケストレーターを使用
    NotificationOrchestrator.send_inventory_alerts(force: threshold.present?)
    
    # 従来のActionCable通知も維持（段階的移行）
    legacy_actioncable_notification if threshold.present?
  end

  private

  def legacy_actioncable_notification
    # 既存のActionCable通知ロジックを保持
    # 段階的に新システムに移行
  end
end
```

## 4. 予測アラート機能

### 4.1 InventoryPredictionService

```ruby
# app/services/inventory_prediction_service.rb
class InventoryPredictionService
  # 単純な線形予測（将来はより高度なアルゴリズムに拡張）
  def self.predict_stockouts(days_ahead: 30)
    new.predict_stockouts(days_ahead)
  end

  def predict_stockouts(days_ahead)
    predictions = []

    Inventory.where('quantity > 0').find_each do |inventory|
      consumption_rate = calculate_consumption_rate(inventory)
      next if consumption_rate <= 0

      predicted_days = inventory.quantity / consumption_rate
      
      if predicted_days <= days_ahead
        predictions << {
          inventory: inventory,
          predicted_stockout_date: predicted_days.days.from_now,
          consumption_rate: consumption_rate,
          confidence_level: calculate_confidence(inventory)
        }
      end
    end

    predictions
  end

  private

  def calculate_consumption_rate(inventory)
    # 過去30日の消費履歴から平均消費率を計算
    recent_logs = inventory.inventory_logs
                          .where(action: 'shipment')
                          .where(created_at: 30.days.ago..Time.current)

    return 0 if recent_logs.empty?

    total_consumed = recent_logs.sum(:quantity_change)
    days_with_activity = recent_logs.group_by(&:date).count

    return 0 if days_with_activity == 0

    total_consumed.abs / 30.0 # 1日平均消費量
  end

  def calculate_confidence(inventory)
    # 履歴データの量と一貫性に基づく信頼度
    log_count = inventory.inventory_logs.count
    
    case log_count
    when 0..5 then 'low'
    when 6..20 then 'medium'
    else 'high'
    end
  end
end
```

## 5. テンプレート例

### 5.1 メールテンプレート

```erb
<!-- app/views/admin_mailer/stock_alert_enhanced.html.erb -->
<h2>在庫アラート通知</h2>

<p>こんにちは、<%= @admin.name %>さん</p>

<p>以下の商品で在庫アラートが発生しています：</p>

<% @alert_data.each do |alert_type, items| %>
  <% next if items.empty? %>
  
  <h3><%= t("stock_alert.alert_types.#{alert_type}") %></h3>
  
  <table border="1" style="border-collapse: collapse; width: 100%;">
    <thead>
      <tr>
        <th>商品名</th>
        <th>現在庫数</th>
        <th>閾値</th>
        <th>カテゴリ</th>
        <th>最終更新</th>
        <% if alert_type == :predicted_stockout %>
          <th>予想在庫切れ日</th>
        <% end %>
      </tr>
    </thead>
    <tbody>
      <% items.each do |item| %>
        <tr>
          <td><%= item[:inventory].name %></td>
          <td style="color: <%= stock_color(item[:current_quantity], item[:threshold]) %>;">
            <%= item[:current_quantity] %>
          </td>
          <td><%= item[:threshold] %></td>
          <td><%= item[:category] %></td>
          <td><%= l(item[:last_updated], format: :short) %></td>
          <% if alert_type == :predicted_stockout %>
            <td style="color: orange;">
              <%= l(item[:predicted_stockout_date], format: :short) if item[:predicted_stockout_date] %>
            </td>
          <% end %>
        </tr>
      <% end %>
    </tbody>
  </table>
<% end %>

<p>
  <a href="<%= admin_inventories_url %>" style="background: #007bff; color: white; padding: 10px 15px; text-decoration: none; border-radius: 4px;">
    在庫管理画面を開く
  </a>
</p>

<hr>
<small>
  この通知は <%= l(@generated_at, format: :long) %> に生成されました。<br>
  通知設定の変更は<a href="<%= edit_admin_notification_settings_url %>">こちら</a>から行えます。
</small>
```

### 5.2 ActionCableメッセージ

```json
{
  "type": "stock_alert",
  "data": {
    "alert_type": "critical_low",
    "message": "5 商品で重要在庫アラートが発生しています",
    "items": [
      {
        "id": 123,
        "name": "Product A",
        "current_quantity": 2,
        "threshold": 5,
        "status": "critical"
      }
    ],
    "severity": "high",
    "timestamp": "2024-06-08T10:30:00Z",
    "actions": [
      {
        "label": "詳細を見る",
        "url": "/admin/inventories?filter=low_stock"
      },
      {
        "label": "発注する",
        "url": "/admin/purchase_orders/new"
      }
    ]
  }
}
```

## 6. 設定統合

### 6.1 ConfigurationServiceとの連携

```yaml
# 在庫アラート関連の設定
inventory:
  alert:
    # 基本閾値
    critical_threshold: 5
    low_threshold: 10
    
    # 予測アラート
    prediction_enabled: true
    prediction_window_days: 30
    min_confidence_level: "medium"
    
    # 配信設定
    batch_notifications: true
    max_items_per_notification: 50
    
    # エスカレーション
    escalation_enabled: true
    escalation_intervals: [1, 4, 24] # 時間
    
    # カテゴリ別設定例
    category:
      medical:
        critical_threshold: 10
        low_threshold: 20
      consumables:
        critical_threshold: 2
        low_threshold: 5
```

## 7. 実装計画

### 7.1 フェーズ1: 基盤強化（2週間）

1. **NotificationDeliveryLog**モデルの作成
2. **NotificationOrchestrator**の実装
3. **既存AdminNotificationSetting**との統合
4. **EnhancedStockAlertJob**の作成と並行運用

### 7.2 フェーズ2: テンプレート拡張（1週間）

1. **メールテンプレート**の実装
2. **ActionCableメッセージ**の拡張
3. **Slackインテグレーション**の基盤
4. **管理画面**での通知履歴表示

### 7.3 フェーズ3: 予測機能（2週間）

1. **InventoryPredictionService**の実装
2. **消費パターン分析**機能
3. **予測アラート**の配信
4. **信頼度指標**の実装

### 7.4 フェーズ4: 高度な機能（3週間）

1. **カテゴリ別閾値管理**
2. **エスカレーション機能**
3. **バッチ通知とサマリー**
4. **パフォーマンス最適化**

## 8. セキュリティとパフォーマンス

### 8.1 セキュリティ考慮事項

- **権限管理**: AdminNotificationSettingによる受信者制御
- **データ暗号化**: 機密性の高い通知内容の暗号化
- **監査ログ**: NotificationDeliveryLogによる完全な追跡
- **レート制限**: 通知スパムの防止

### 8.2 パフォーマンス最適化

- **バッチ処理**: 大量商品の効率的な処理
- **キャッシング**: 設定値と計算結果のキャッシュ
- **非同期処理**: Sidekiqによるバックグラウンド実行
- **データベース最適化**: 適切なインデックスとクエリ最適化

## 9. テスト戦略

### 9.1 単体テスト例

```ruby
# spec/services/notification_orchestrator_spec.rb
RSpec.describe NotificationOrchestrator do
  describe '#send_inventory_alerts' do
    let(:admin) { create(:admin) }
    let(:inventory) { create(:inventory, quantity: 3) }
    
    before do
      create(:admin_notification_setting,
             admin: admin,
             notification_type: 'stock_alert',
             delivery_method: 'email',
             priority: 'high')
    end

    it 'sends alerts to configured admins' do
      expect { described_class.send_inventory_alerts }
        .to change { NotificationDeliveryLog.count }.by(1)
    end

    it 'respects notification settings' do
      # 設定に基づく配信テスト
    end
  end
end
```

### 9.2 統合テスト

- **エンドツーエンド通知フロー**のテスト
- **レート制限**の動作確認
- **エラーハンドリング**の検証
- **パフォーマンス**のベンチマーク

## 10. 監視とメトリクス

### 10.1 主要メトリクス

- **通知配信成功率**
- **配信レイテンシ**
- **アラート精度**（予測の的中率）
- **管理者の応答時間**

### 10.2 アラート設定

- **配信失敗率**が10%を超えた場合
- **アラート量**が異常に増加した場合
- **予測精度**が低下した場合

## 11. 決定事項と根拠

### なぜ既存のAdminNotificationSettingを拡張するか？

**Before**: 新しい通知システムを一から構築
**After**: 既存のAdminNotificationSettingを中核とした拡張
**理由**:
- 既に充実した機能（レート制限、優先度管理等）が存在
- 管理者の学習コストを最小化
- 他の通知タイプとの一貫性維持
- 段階的移行によるリスク軽減

### なぜオーケストレーターパターンを採用するか？

**Before**: 各ジョブが個別に通知を送信
**After**: NotificationOrchestratorによる一元管理
**理由**:
- 複数のアラートタイプを統合的に処理
- バッチング効率の向上
- エラーハンドリングの一元化
- 将来の拡張性確保

## 12. 将来の拡張計画

### 12.1 AI/ML統合

- **需要予測**の高度化
- **異常検知**による自動アラート
- **最適発注量**の提案

### 12.2 外部連携

- **ERPシステム**との連携
- **サプライヤー**への自動発注
- **IoTセンサー**からのリアルタイム在庫データ

### 12.3 ユーザビリティ向上

- **モバイルアプリ**でのプッシュ通知
- **ダッシュボード**の個人化
- **音声アシスタント**との連携

## 13. まとめ

本設計により、StockRxの在庫アラート機能は以下の改善を実現する：

1. **統合性**: 既存の優れた通知基盤を活用した一貫性のあるシステム
2. **柔軟性**: カテゴリ別閾値と予測アラートによるプロアクティブな管理
3. **拡張性**: オーケストレーターパターンによる将来の機能追加への対応
4. **運用性**: 詳細な配信ログと設定管理による運用負荷の軽減

段階的な実装により、既存システムの安定性を保ちながら、大幅な機能向上を達成できる。