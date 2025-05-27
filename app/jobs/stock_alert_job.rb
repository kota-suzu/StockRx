# frozen_string_literal: true

# ============================================
# Stock Alert Notification Job
# ============================================
# 在庫不足アラートのバックグラウンド通知処理
# ApplicationJobの基盤を活用したSidekiq対応ジョブの実装例
# 定期実行対応：sidekiq-scheduler経由で毎日実行

class StockAlertJob < ApplicationJob
  include ProgressNotifier

  # ============================================
  # Sidekiq Configuration
  # ============================================
  queue_as :notifications

  # Sidekiq specific options
  sidekiq_options retry: 2, backtrace: true, queue: :notifications

  # @param threshold [Integer] 在庫アラート閾値
  # @param admin_ids [Array<Integer>] 通知対象の管理者ID配列
  # @param enable_email [Boolean] メール通知を有効にするか（デフォルト：false）
  def perform(threshold = 10, admin_ids = [], enable_email = false)
    # 進捗追跡の初期化
    job_id = self.job_id || SecureRandom.uuid
    admin_id = admin_ids.first || Admin.first&.id  # 通知用の管理者ID

    status_key = initialize_progress(admin_id, job_id, "stock_alert", {
      threshold: threshold,
      enable_email: enable_email
    }) if admin_id

    Rails.logger.info "Starting stock alert check with threshold: #{threshold}"

    # 在庫不足商品を検索
    low_stock_items = find_low_stock_items(threshold)
    out_of_stock_items = find_out_of_stock_items

    return if low_stock_items.empty? && out_of_stock_items.empty?

    # 管理者が指定されていない場合は全管理者に通知
    target_admins = admin_ids.present? ? Admin.where(id: admin_ids) : Admin.all

    # 通知処理
    notification_results = []

    target_admins.each do |admin|
      result = send_stock_alert(admin, low_stock_items, out_of_stock_items, threshold, enable_email)
      notification_results << result
    end

    # 結果をログに記録
    Rails.logger.info({
      event: "stock_alert_completed",
      low_stock_count: low_stock_items.count,
      out_of_stock_count: out_of_stock_items.count,
      notifications_sent: notification_results.count(&:itself),
      threshold: threshold,
      email_enabled: enable_email
    }.to_json)

    # 完了通知
    if status_key && admin_id
      notify_completion(status_key, admin_id, "stock_alert", {
        low_stock_count: low_stock_items.count,
        out_of_stock_count: out_of_stock_items.count,
        notifications_sent: notification_results.count(&:itself)
      })
    end

    {
      low_stock_items: low_stock_items,
      out_of_stock_items: out_of_stock_items,
      notifications_sent: notification_results.count(&:itself),
      threshold: threshold
    }
  end

  private

  def find_low_stock_items(threshold)
    # パフォーマンス最適化：必要なフィールドのみ取得
    Inventory.where("quantity <= ?", threshold)
             .select(:id, :name, :quantity, :price)
             .order(:quantity, :name)
  end

  def find_out_of_stock_items
    # 完全に在庫切れの商品
    Inventory.where(quantity: 0)
             .select(:id, :name, :quantity, :price)
             .order(:quantity, :name)
  end

  def send_stock_alert(admin, low_stock_items, out_of_stock_items, threshold, enable_email)
    begin
      # ActionCable経由でリアルタイム通知
      send_realtime_notification(admin, low_stock_items, out_of_stock_items, threshold)

      # メール通知（有効な場合のみ）
      if enable_email
        send_email_notification(admin, low_stock_items, out_of_stock_items, threshold)
      end

      Rails.logger.info "Stock alert sent to admin #{admin.id} (email: #{enable_email})"
      true

    rescue => e
      Rails.logger.error "Failed to send stock alert to admin #{admin.id}: #{e.message}"
      false
    end
  end

  def send_realtime_notification(admin, low_stock_items, out_of_stock_items, threshold)
    ActionCable.server.broadcast("admin_#{admin.id}", {
      type: "stock_alert",
      message: I18n.t("jobs.stock_alert.message",
                     count: low_stock_items.count + out_of_stock_items.count,
                     threshold: threshold),
      items: format_items_for_notification(low_stock_items.limit(5) + out_of_stock_items.limit(5)),
      total_count: low_stock_items.count + out_of_stock_items.count,
      threshold: threshold,
      timestamp: Time.current.iso8601
    })
  end

  def send_email_notification(admin, low_stock_items, out_of_stock_items, threshold)
    # AdminMailerを使用してメール送信
    AdminMailer.stock_alert(admin, low_stock_items, out_of_stock_items, threshold).deliver_now
  rescue => e
    Rails.logger.warn "Failed to send email notification to admin #{admin.id}: #{e.message}"
    # メール送信失敗は通知全体を失敗とは見なさない
  end

  def format_items_for_notification(items)
    items.map do |item|
      {
        id: item.id,
        name: item.name,
        quantity: item.quantity,
        price: item.price,
        status: determine_stock_status(item.quantity)
      }
    end
  end

  def determine_stock_status(quantity)
    case quantity
    when 0 then "out_of_stock"
    when 1..5 then "critical"
    when 6..10 then "low"
    else "normal"
    end
  end

  # TODO: 将来的な機能拡張
  # ============================================
  # 1. 高度なアラート設定
  #    - 商品カテゴリ別の閾値設定
  #    - 重要度別の通知チャンネル選択
  #    - 通知頻度の制御（重複防止）
  #    - VIP商品の優先アラート機能
  #
  # 2. 予測アラート機能
  #    - 在庫減少トレンドの分析
  #    - 発注タイミングの提案
  #    - 季節性を考慮した在庫予測
  #    - 機械学習による需要予測
  #
  # 3. 外部連携機能
  #    - Slack/Teams通知
  #    - SMS緊急通知
  #    - 発注システム自動連携
  #    - POS システムとの連携
  #
  # 4. 分析・レポート機能
  #    - 在庫切れ頻度分析
  #    - アラート効果測定
  #    - 発注最適化提案
  #    - コスト影響分析
  #
  # 5. ユーザビリティ向上
  #    - ワンクリック発注機能
  #    - 在庫予測グラフ表示
  #    - カスタマイズ可能な通知設定
  #    - モバイルアプリ連携

  # def categorized_alert_thresholds
  #   # 商品カテゴリ別の閾値設定例
  #   {
  #     'medicine' => 5,      # 医薬品は早めにアラート
  #     'supplement' => 10,   # サプリメントは標準
  #     'cosmetic' => 15,     # 化粧品は余裕をもって
  #     'other' => 10         # その他は標準
  #   }
  # end
  #
  # def find_low_stock_by_category(threshold)
  #   # カテゴリ別在庫不足検索
  #   categorized_alert_thresholds.flat_map do |category, cat_threshold|
  #     Inventory.joins(:category)
  #              .where(categories: { name: category })
  #              .where("inventories.quantity <= ?", cat_threshold)
  #   end
  # end
end

# ============================================
# TODO: 在庫アラートシステムの機能拡張（優先度：高）
# REF: doc/remaining_tasks.md - 機能拡張・UX改善
# ============================================
# 1. 動的閾値管理（優先度：高）
#    - 商品カテゴリ別の在庫閾値設定
#    - 販売パターンに基づく動的閾値調整
#    - 季節要因を考慮した閾値最適化
#    - ABC分析による重要度別管理
#
# def calculate_dynamic_threshold(item)
#   # 過去の販売データから予測
#   sales_history = InventoryLog.where(inventory: item)
#                              .where('created_at > ?', 3.months.ago)
#                              .where('quantity_change < 0')
#
#   # 平均販売速度を計算
#   avg_daily_sales = sales_history.sum(:quantity_change).abs / 90.0
#
#   # リードタイム（発注〜納品）を考慮
#   lead_time_days = item.supplier&.lead_time || 7
#   safety_factor = 1.5 # 安全係数
#
#   # 動的閾値 = 平均販売速度 × リードタイム × 安全係数
#   dynamic_threshold = (avg_daily_sales * lead_time_days * safety_factor).ceil
#
#   # 最小・最大閾値の制限
#   [dynamic_threshold, item.minimum_quantity || 10].max
# end
#
# 2. 予測分析・自動発注（優先度：高）
#    - 在庫切れ予測アルゴリズム
#    - 自動発注タイミングの提案
#    - サプライヤー別の最適発注量計算
#    - 発注コスト最適化
#
# def predict_stockout_date(item)
#   recent_consumption = calculate_consumption_rate(item)
#   return nil if recent_consumption <= 0
#
#   days_until_stockout = item.quantity / recent_consumption
#   Date.current + days_until_stockout.days
# end
#
# def generate_reorder_suggestion(item)
#   predicted_stockout = predict_stockout_date(item)
#   supplier_lead_time = item.supplier&.lead_time || 7
#
#   if predicted_stockout && predicted_stockout <= Date.current + supplier_lead_time.days
#     {
#       urgency: :high,
#       suggested_quantity: calculate_optimal_order_quantity(item),
#       reason: "#{predicted_stockout}に在庫切れ予測",
#       supplier: item.supplier,
#       estimated_cost: calculate_order_cost(item)
#     }
#   end
# end
#
# 3. 通知のカスタマイズ強化（優先度：中）
#    - AdminNotificationSetting との連携
#    - 在庫レベル別の通知優先度設定
#    - 時間帯別通知制御
#    - 担当者別の商品カテゴリ通知
#
# def send_personalized_alerts(items_by_urgency)
#   items_by_urgency.each do |urgency, items|
#     # 該当する通知設定を持つ管理者を取得
#     target_admins = AdminNotificationSetting
#                    .admins_for_notification(
#                      'stock_alert',
#                      nil,
#                      urgency_to_priority(urgency)
#                    )
#
#     target_admins.each do |admin|
#       # 管理者の担当カテゴリをフィルタ
#       relevant_items = filter_by_admin_category(admin, items)
#       next if relevant_items.empty?
#
#       send_customized_alert(admin, relevant_items, urgency)
#     end
#   end
# end
#
# def urgency_to_priority(urgency)
#   case urgency
#   when :critical then :critical
#   when :high then :high
#   when :medium then :medium
#   else :low
#   end
# end
#
# 4. サプライヤー連携機能（優先度：中）
#    - サプライヤーへの自動発注メール
#    - EDI（電子データ交換）システム連携
#    - 発注書の自動生成
#    - 納期管理・追跡機能
#
# def auto_notify_suppliers(reorder_suggestions)
#   reorder_suggestions.group_by(&:supplier).each do |supplier, suggestions|
#     next unless supplier&.auto_ordering_enabled?
#
#     # サプライヤー向け発注データの生成
#     order_data = suggestions.map do |suggestion|
#       {
#         item_code: suggestion.item.code,
#         item_name: suggestion.item.name,
#         suggested_quantity: suggestion.suggested_quantity,
#         current_stock: suggestion.item.quantity,
#         urgency: suggestion.urgency
#       }
#     end
#
#     # EDIシステムへの送信 or メール送信
#     if supplier.edi_enabled?
#       EDIService.send_order_request(supplier, order_data)
#     else
#       SupplierMailer.reorder_notification(supplier, order_data).deliver_now
#     end
#
#     # 発注履歴の記録
#     PurchaseOrder.create!(
#       supplier: supplier,
#       items: order_data,
#       status: 'auto_suggested',
#       total_amount: calculate_estimated_total(order_data)
#     )
#   end
# end
#
# 5. 在庫最適化分析（優先度：中）
#    - ABC分析（売上貢献度別分類）
#    - デッドストック検出
#    - 回転率分析
#    - キャッシュフロー影響分析
#
# def perform_abc_analysis
#   # 過去12ヶ月の売上データに基づくABC分析
#   items_with_revenue = Inventory.joins(:inventory_logs)
#                               .where('inventory_logs.created_at > ?', 12.months.ago)
#                               .group('inventories.id')
#                               .select('inventories.*, SUM(inventory_logs.quantity_change * inventories.price) as total_revenue')
#                               .order('total_revenue DESC')
#
#   total_revenue = items_with_revenue.sum(&:total_revenue)
#   cumulative_percentage = 0
#
#   items_with_revenue.each_with_index do |item, index|
#     item_percentage = (item.total_revenue / total_revenue) * 100
#     cumulative_percentage += item_percentage
#
#     # ABC分類の決定
#     abc_category = case cumulative_percentage
#                   when 0..80 then 'A'  # 売上の80%を占める重要商品
#                   when 80..95 then 'B' # 売上の15%を占める中重要商品
#                   else 'C'             # 売上の5%を占める低重要商品
#                   end
#
#     item.update!(abc_category: abc_category)
#   end
# end
#
# def detect_dead_stock(months_threshold = 6)
#   # 指定期間内に動きがない商品を検出
#   dead_stock_items = Inventory.left_joins(:inventory_logs)
#                              .where('inventory_logs.created_at IS NULL OR inventory_logs.created_at < ?', months_threshold.months.ago)
#                              .where('quantity > 0')
#
#   # デッドストック通知
#   if dead_stock_items.any?
#     AdminChannel.broadcast_to("admin_notifications", {
#       type: "dead_stock_alert",
#       items_count: dead_stock_items.count,
#       estimated_value: dead_stock_items.sum { |item| item.quantity * item.price },
#       recommendations: generate_dead_stock_recommendations(dead_stock_items)
#     })
#   end
# end
#
# 6. レポート・ダッシュボード機能（優先度：中）
#    - 在庫状況ダッシュボード
#    - 在庫回転率レポート
#    - 発注提案レポート
#    - 在庫コスト分析
#
# def generate_inventory_dashboard
#   dashboard_data = {
#     summary: {
#       total_items: Inventory.active.count,
#       low_stock_count: find_low_stock_items.count,
#       out_of_stock_count: find_out_of_stock_items.count,
#       total_value: Inventory.active.sum('quantity * price')
#     },
#
#     turnover_analysis: calculate_turnover_rates,
#     abc_distribution: Inventory.group(:abc_category).count,
#     supplier_performance: analyze_supplier_performance,
#
#     alerts: {
#       urgent_reorders: generate_urgent_reorder_list,
#       dead_stock_items: detect_dead_stock(3),
#       overstocked_items: detect_overstock
#     }
#   }
#
#   # ダッシュボードデータをキャッシュ
#   Rails.cache.write('inventory_dashboard', dashboard_data, expires_in: 30.minutes)
#
#   dashboard_data
# end
#
# 7. 自動化・ワークフロー（優先度：高）
#    - 段階的アラートエスカレーション
#    - 承認ワークフローの自動化
#    - 緊急時の自動対応
#    - 監査ログの強化
#
# def escalate_critical_alerts
#   critical_items = find_critical_stock_items
#
#   critical_items.each do |item|
#     # 段階的エスカレーション
#     case item.alert_level
#     when 0 # 初回アラート
#       send_initial_alert(item)
#       item.update!(alert_level: 1, last_alert_at: Time.current)
#
#     when 1 # 2回目（1時間後）
#       if item.last_alert_at < 1.hour.ago
#         send_supervisor_alert(item)
#         item.update!(alert_level: 2, last_alert_at: Time.current)
#       end
#
#     when 2 # 3回目（管理者アラート）
#       if item.last_alert_at < 4.hours.ago
#         send_manager_alert(item)
#         item.update!(alert_level: 3, last_alert_at: Time.current)
#       end
#     end
#   end
# end
#
# def auto_approve_urgent_orders
#   urgent_orders = PurchaseOrder.where(status: 'pending', urgency: :critical)
#
#   urgent_orders.each do |order|
#     # 自動承認条件の確認
#     if order.total_amount <= auto_approval_limit &&
#        order.supplier.trusted? &&
#        order.items.all? { |item| item.abc_category == 'A' }
#
#       order.update!(
#         status: 'auto_approved',
#         approved_by: 'system',
#         approved_at: Time.current
#       )
#
#       # 自動承認の監査ログ
#       AuditLog.create!(
#         auditable: order,
#         action: 'auto_approved',
#         message: "緊急発注が自動承認されました（総額: #{order.total_amount}円）",
#         user_id: nil,
#         operation_source: 'system'
#       )
#     end
#   end
# end
