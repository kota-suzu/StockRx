#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================
# メール送信テストスクリプト
# ============================================
# 開発環境でのメール配信機能をテスト
#
# 使用方法:
#   ruby test_mail_delivery.rb
#
# 環境変数:
#   MAIL_DELIVERY_METHOD - メール配信方法 (smtp, letter_opener, test, log)
#   SMTP_ADDRESS         - SMTPサーバーアドレス
#   SMTP_PORT           - SMTPポート番号

require_relative 'config/environment'

class MailDeliveryTester
  def self.run
    new.run
  end

  def initialize
    @admin = Admin.first || create_test_admin
    @delivery_method = ENV.fetch('MAIL_DELIVERY_METHOD', 'letter_opener')
  end

  def run
    puts "🧪 メール送信テスト開始"
    puts "配信方法: #{@delivery_method}"
    puts "管理者: #{@admin.email}"
    puts "-" * 50

    test_cases = [
      { name: "CSV インポート完了通知", method: :test_csv_import_notification },
      { name: "在庫アラート通知", method: :test_stock_alert },
      { name: "期限切れアラート通知", method: :test_expiry_alert },
      { name: "月次レポート通知", method: :test_monthly_report },
      { name: "セキュリティアラート通知", method: :test_security_alert }
    ]

    test_cases.each do |test_case|
      begin
        puts "\n📧 テスト: #{test_case[:name]}"
        result = send(test_case[:method])
        puts "✅ 送信成功: #{result}"
      rescue => e
        puts "❌ 送信失敗: #{e.message}"
        puts "   #{e.backtrace.first}"
      end
    end

    display_access_instructions
  end

  private

  def test_csv_import_notification
    import_result = {
      valid_count: 150,
      invalid_records: [
        { row: 5, errors: [ "価格が不正です" ] },
        { row: 12, errors: [ "商品名が空です" ] }
      ]
    }

    AdminMailer.csv_import_complete(@admin, import_result).deliver_now
    "CSVインポート完了通知 (成功: #{import_result[:valid_count]}件)"
  end

  def test_stock_alert
    # テスト用の在庫不足商品データを作成
    low_stock_items = create_sample_inventories(5, quantity: 2)
    threshold = 5

    AdminMailer.stock_alert(@admin, low_stock_items, threshold).deliver_now
    "在庫アラート (#{low_stock_items.count}件の低在庫商品)"
  end

  def test_expiry_alert
    # テスト用の期限切れ商品データ
    expiring_items = create_sample_inventories(3, expiring: true)
    expired_items = create_sample_inventories(2, expired: true)
    days_ahead = 7

    AdminMailer.expiry_alert(@admin, expiring_items, expired_items, days_ahead).deliver_now
    "期限切れアラート (期限間近: #{expiring_items.count}件, 期限切れ: #{expired_items.count}件)"
  end

  def test_monthly_report
    target_date = Date.current.beginning_of_month
    report_file = create_sample_report_file
    report_data = generate_sample_report_data(target_date)

    AdminMailer.monthly_report_complete(@admin, report_file, report_data).deliver_now
    "月次レポート (#{target_date.strftime('%Y年%m月')})"
  end

  def test_security_alert
    error_details = {
      error_class: "SecurityError",
      error_message: "不正なアクセスが検出されました",
      occurred_at: Time.current,
      ip_address: "192.168.1.100",
      user_agent: "Mozilla/5.0 (Test Browser)"
    }

    AdminMailer.system_error_alert(@admin, error_details).deliver_now
    "セキュリティアラート (#{error_details[:error_class]})"
  end

  def create_test_admin
    Admin.create!(
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123",
      name: "テスト管理者"
    )
  rescue => e
    puts "⚠️  テスト管理者の作成に失敗: #{e.message}"
    puts "    既存の管理者を使用します"
    Admin.first!
  end

  def create_sample_inventories(count, options = {})
    inventories = []

    count.times do |i|
      inventory = {
        id: i + 1,
        name: "テスト商品#{i + 1}",
        quantity: options[:quantity] || rand(1..10),
        price: rand(100..1000)
      }

      if options[:expiring]
        inventory[:expires_on] = Date.current + rand(1..7).days
      elsif options[:expired]
        inventory[:expires_on] = Date.current - rand(1..30).days
      end

      inventories << OpenStruct.new(inventory)
    end

    inventories
  end

  def create_sample_report_file
    # 一時的なレポートファイルを作成
    temp_file = Rails.root.join("tmp", "sample_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.pdf")

    File.write(temp_file, "Sample Report Content")
    temp_file.to_s
  end

  def generate_sample_report_data(target_date)
    {
      target_date: target_date,
      inventory_summary: {
        total_items: 1250,
        total_value: 2_500_000,
        low_stock_items: 15,
        out_of_stock_items: 3
      },
      expiry_analysis: {
        expiring_next_month: 8,
        expired_items: 2
      },
      performance_metrics: {
        average_turnover: 4.2,
        best_performing_category: "電子機器",
        improvement_areas: [ "在庫回転率", "期限管理" ]
      }
    }
  end

  def display_access_instructions
    puts "\n" + "=" * 50
    puts "📋 メール確認方法:"
    puts "=" * 50

    case @delivery_method
    when 'letter_opener'
      puts "🌐 Letter Opener: メールが自動でブラウザに表示されます"
      puts "📝 Letter Opener Web: http://localhost:3000/letter_opener"

    when 'smtp'
      smtp_address = ENV.fetch('SMTP_ADDRESS', 'localhost')
      smtp_port = ENV.fetch('SMTP_PORT', '1025')
      web_port = smtp_port.to_i + 7000  # 通常 8025

      puts "📨 SMTP サーバー: #{smtp_address}:#{smtp_port}"
      puts "🌐 Web UI (MailHog): http://localhost:#{web_port}"
      puts "🌐 Web UI (MailTrap): http://localhost:#{web_port}"

    when 'test'
      puts "📝 テストモード: メールは送信されていません"
      puts "📊 ActionMailer::Base.deliveries で確認可能"

    when 'log'
      puts "📝 ログモード: メール内容がログに出力されています"
      puts "📂 ログファイル: log/development.log"
    end

    puts "\n🔧 配信方法の切り替え:"
    puts "   MAIL_DELIVERY_METHOD=smtp ruby test_mail_delivery.rb"
    puts "   MAIL_DELIVERY_METHOD=letter_opener ruby test_mail_delivery.rb"
    puts "\n💡 MailHog起動: mailhog"
    puts "💡 Docker MailTrap: docker-compose --profile dev up mailtrap"
  end
end

# スクリプト実行
if __FILE__ == $0
  MailDeliveryTester.run
end
