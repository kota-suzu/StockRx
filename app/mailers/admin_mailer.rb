# frozen_string_literal: true

# ============================================
# Admin Mailer for StockRx
# ============================================
# 管理者向けメール通知機能
# 在庫アラート・システム通知・レポート配信

class AdminMailer < ApplicationMailer
  # ============================================
  # 在庫関連通知
  # ============================================

  # CSVインポート完了通知
  # @param admin [Admin] 通知対象の管理者
  # @param import_result [Hash] インポート結果
  def csv_import_complete(admin, import_result)
    @admin = admin
    @import_result = import_result
    @valid_count = import_result[:valid_count]
    @invalid_count = import_result[:invalid_records]&.size || 0

    mail(
      **admin_mail_defaults(admin),
      subject: I18n.t("admin_mailer.csv_import_complete.subject",
                      valid_count: @valid_count,
                      invalid_count: @invalid_count)
    )
  end

  # 在庫不足アラート通知
  # @param admin [Admin] 通知対象の管理者
  # @param low_stock_items [Array] 在庫不足商品一覧
  # @param threshold [Integer] 在庫アラート閾値
  def stock_alert(admin, low_stock_items, threshold)
    @admin = admin
    @low_stock_items = low_stock_items
    @threshold = threshold
    @total_count = low_stock_items.count

    mail(
      **admin_mail_defaults(admin),
      subject: I18n.t("admin_mailer.stock_alert.subject",
                      count: @total_count,
                      threshold: threshold)
    )
  end

  # 期限切れアラート通知
  # @param admin [Admin] 通知対象の管理者
  # @param expiring_items [Array] 期限切れ予定商品
  # @param expired_items [Array] 既に期限切れの商品
  # @param days_ahead [Integer] 何日前からアラートするか
  def expiry_alert(admin, expiring_items, expired_items, days_ahead)
    @admin = admin
    @expiring_items = expiring_items
    @expired_items = expired_items
    @days_ahead = days_ahead
    @expiring_count = expiring_items.count
    @expired_count = expired_items.count

    mail(
      **urgent_mail_defaults.merge(admin_mail_defaults(admin)),
      subject: I18n.t("admin_mailer.expiry_alert.subject",
                      expiring_count: @expiring_count,
                      expired_count: @expired_count)
    )
  end

  # ============================================
  # レポート関連通知
  # ============================================

  # 月次レポート完成通知
  # @param admin [Admin] 通知対象の管理者
  # @param report_file [String] レポートファイルパス
  # @param report_data [Hash] レポートデータ
  def monthly_report_complete(admin, report_file, report_data)
    @admin = admin
    @report_data = report_data
    @report_month = report_data[:target_date]&.strftime("%Y年%m月") || "不明"

    # レポートファイルを添付
    if File.exist?(report_file)
      attachments[File.basename(report_file)] = File.read(report_file)
    end

    mail(
      **admin_mail_defaults(admin),
      subject: I18n.t("admin_mailer.monthly_report_complete.subject",
                      month: @report_month)
    )
  end

  # ============================================
  # システム通知
  # ============================================

  # システムメンテナンス通知
  # @param admin [Admin] 通知対象の管理者
  # @param maintenance_results [Hash] メンテナンス結果
  def sidekiq_maintenance_report(admin, maintenance_results)
    @admin = admin
    @maintenance_results = maintenance_results
    @stats = maintenance_results[:stats]
    @recommendations = maintenance_results[:recommendations]

    mail(
      **system_mail_defaults.merge(admin_mail_defaults(admin)),
      subject: I18n.t("admin_mailer.sidekiq_maintenance_report.subject")
    )
  end

  # システムエラー通知
  # @param admin [Admin] 通知対象の管理者
  # @param error_details [Hash] エラー詳細
  def system_error_alert(admin, error_details)
    @admin = admin
    @error_details = error_details
    @error_class = error_details[:error_class]
    @error_message = error_details[:error_message]
    @occurred_at = error_details[:occurred_at]

    mail(
      **urgent_mail_defaults.merge(admin_mail_defaults(admin)),
      subject: I18n.t("admin_mailer.system_error_alert.subject",
                      error_class: @error_class)
    )
  end

  # ============================================
  # 認証・セキュリティ関連通知
  # ============================================

  # パスワードリセット通知
  # @param admin [Admin] 通知対象の管理者
  def password_reset_instructions(admin)
    @admin = admin
    @reset_url = edit_admin_password_url(admin, reset_password_token: admin.reset_password_token)

    mail(
      **admin_mail_defaults(admin),
      subject: I18n.t("admin_mailer.password_reset_instructions.subject")
    )
  end

  # アカウントロック通知
  # @param admin [Admin] 通知対象の管理者
  def account_locked(admin)
    @admin = admin
    @unlock_url = unlock_admin_url(admin, unlock_token: admin.unlock_token)

    mail(
      **urgent_mail_defaults.merge(admin_mail_defaults(admin)),
      subject: I18n.t("admin_mailer.account_locked.subject")
    )
  end

  # TODO: 将来的な機能拡張
  # ============================================
  # 1. 高度な通知機能
  #    - 通知設定の個人カスタマイズ
  #    - 通知頻度の制御（日次・週次まとめ）
  #    - 重要度別の配信方法選択
  #
  # 2. レポート機能強化
  #    - インタラクティブHTMLレポート
  #    - グラフ・チャート付きレポート
  #    - カスタムレポートテンプレート
  #
  # 3. 外部連携通知
  #    - Slack/Teams連携
  #    - SMS緊急通知
  #    - プッシュ通知連携
  #
  # 4. 分析・改善機能
  #    - メール開封率分析
  #    - 最適な配信時間分析
  #    - A/Bテスト機能

  private

  # メール内容の共通検証
  def validate_email_content
    # メール内容の基本検証
    if subject.blank?
      raise ArgumentError, "メール件名が設定されていません"
    end

    if mail.to.blank?
      raise ArgumentError, "送信先が設定されていません"
    end
  end
end
