#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================
# StockRx セキュリティ対策 動作確認スクリプト
# ============================================
# 目的: ActiveJobのログ出力で機密情報がフィルタリングされることを実証
# 確認項目: 引数の平文出力防止、機密情報のマスキング動作
#
# セキュリティベストプラクティス:
# - 本番環境では実際のAPIキーは環境変数から取得すること
#   例: ENV['STRIPE_API_KEY'] や Rails.application.credentials.stripe[:api_key]
# - テストでは明らかにダミーとわかる値を使用（例: test_token_xxx）
# - GitHubのシークレットスキャニングを回避するため実際のキーパターンは避ける

require_relative './config/environment'
require 'logger'
require 'stringio'

class SecurityVerificationTest
  attr_reader :results

  def initialize
    @results = {}
    @original_logger = Rails.logger
    @captured_logs = StringIO.new
    @test_logger = Logger.new(@captured_logs)
    @test_logger.level = Logger::INFO
  end

  def run_all_tests
    puts "🔒 StockRx セキュリティ対策 動作確認開始"
    puts "=" * 60

    test_basic_argument_filtering
    test_import_job_security
    test_api_job_security
    test_nested_sensitive_data
    test_performance_impact

    display_results
  end

  private

  def test_basic_argument_filtering
    puts "\n📋 テスト1: 基本的な引数フィルタリング"

    # テスト用の機密情報（本物のAPIキーではありません）
    sensitive_args = [
      'public_data',
      {
        api_token: 'test_token_abcdefghijklmnopqrstuvwx',
        password: 'super_secret_password',
        client_secret: 'test_secret_123456789',
        user_email: 'admin@company.com'
      }
    ]

     # ログキャプチャ開始
     capture_logs do
       # TestJobクラスを定義（動的）
       test_job_class = Class.new(ApplicationJob) do
         def perform(*args)
           Rails.logger.info "Test job executed with args"
         end
       end

       # 定数として定義
       Object.const_set('TestSecurityJob', test_job_class) unless defined?(TestSecurityJob)

       # ジョブ実行
       TestSecurityJob.perform_now(*sensitive_args)
     end

    # ログ内容をチェック
    log_content = @captured_logs.string
    @results[:basic_filtering] = {
      api_token_filtered: !log_content.include?('test_token_abcdefghijklmnopqrstuvwx'),
      password_filtered: !log_content.include?('super_secret_password'),
      secret_filtered: !log_content.include?('test_secret_123456789'),
      email_filtered: !log_content.include?('admin@company.com'),
      filter_marker_present: log_content.include?('[FILTERED]')
    }

    puts "  ✅ APIトークン フィルタリング: #{@results[:basic_filtering][:api_token_filtered] ? '成功' : '失敗'}"
    puts "  ✅ パスワード フィルタリング: #{@results[:basic_filtering][:password_filtered] ? '成功' : '失敗'}"
    puts "  ✅ シークレット フィルタリング: #{@results[:basic_filtering][:secret_filtered] ? '成功' : '失敗'}"
    puts "  ✅ メールアドレス フィルタリング: #{@results[:basic_filtering][:email_filtered] ? '成功' : '失敗'}"
    puts "  ✅ フィルターマーカー存在: #{@results[:basic_filtering][:filter_marker_present] ? '確認' : '未確認'}"
  end

  def test_import_job_security
    puts "\n📁 テスト2: ImportInventoriesJob セキュリティ"

    # 管理者を取得または作成
    admin = Admin.first || create_test_admin

    sensitive_import_args = [
      '/var/app/sensitive/import_file.csv',
      admin.id,
      {
        admin_credentials: 'admin_secret_key',
        file_content: 'sensitive_csv_data_here'
      }
    ]

    capture_logs do
      # ImportInventoriesJobをシミュレート
      begin
        ImportInventoriesJob.perform_now(*sensitive_import_args)
      rescue => e
        # ファイルが存在しないエラーは想定内
        Rails.logger.info "Expected file error: #{e.class.name}"
      end
    end

    log_content = @captured_logs.string
    @results[:import_job_security] = {
      file_path_protected: !log_content.include?('/var/app/sensitive/'),
      admin_credentials_filtered: !log_content.include?('admin_secret_key'),
      file_content_filtered: !log_content.include?('sensitive_csv_data_here'),
      security_validation_logged: log_content.include?('security_validated') || log_content.include?('Security')
    }

    puts "  ✅ ファイルパス保護: #{@results[:import_job_security][:file_path_protected] ? '成功' : '失敗'}"
    puts "  ✅ 管理者認証情報保護: #{@results[:import_job_security][:admin_credentials_filtered] ? '成功' : '失敗'}"
    puts "  ✅ ファイル内容保護: #{@results[:import_job_security][:file_content_filtered] ? '成功' : '失敗'}"
  end

  def test_api_job_security
    puts "\n🌐 テスト3: ExternalApiSyncJob セキュリティ"

    sensitive_api_args = [
      'supplier_api',
      'sync_inventory',
      {
        api_token: 'test_supplier_key_123456789',
        webhook_secret: 'whsec_test_secret',
        credentials: {
          username: 'api_user',
          password: 'api_password_secret'
        }
      }
    ]

    capture_logs do
      ExternalApiSyncJob.perform_now(*sensitive_api_args)
    end

    log_content = @captured_logs.string
    @results[:api_job_security] = {
      api_token_filtered: !log_content.include?('test_supplier_key_123456789'),
      webhook_secret_filtered: !log_content.include?('whsec_test_secret'),
      username_filtered: !log_content.include?('api_user'),
      password_filtered: !log_content.include?('api_password_secret')
    }

    puts "  ✅ APIトークン保護: #{@results[:api_job_security][:api_token_filtered] ? '成功' : '失敗'}"
    puts "  ✅ Webhookシークレット保護: #{@results[:api_job_security][:webhook_secret_filtered] ? '成功' : '失敗'}"
    puts "  ✅ ユーザー名保護: #{@results[:api_job_security][:username_filtered] ? '成功' : '失敗'}"
    puts "  ✅ パスワード保護: #{@results[:api_job_security][:password_filtered] ? '成功' : '失敗'}"
  end

  def test_nested_sensitive_data
    puts "\n🔄 テスト4: ネストした機密データ"

    nested_args = [
      {
        level1: {
          level2: {
            api_key: 'nested_secret_key_123',
            user_info: {
              email: 'nested@secret.com',
              password: 'nested_password'
            }
          }
        },
        config: {
          database_url: 'postgres://user:secret@localhost/db'
        }
      }
    ]

     # テスト用ジョブクラス
     nested_job_class = Class.new(ApplicationJob) do
       def perform(data)
         Rails.logger.info "Processing nested data"
       end
     end
     Object.const_set('NestedTestJob', nested_job_class) unless defined?(NestedTestJob)

    capture_logs do
      NestedTestJob.perform_now(*nested_args)
    end

    log_content = @captured_logs.string
    @results[:nested_security] = {
      nested_api_key_filtered: !log_content.include?('nested_secret_key_123'),
      nested_email_filtered: !log_content.include?('nested@secret.com'),
      nested_password_filtered: !log_content.include?('nested_password'),
      database_url_filtered: !log_content.include?('postgres://user:secret@localhost')
    }

    puts "  ✅ ネストAPIキー保護: #{@results[:nested_security][:nested_api_key_filtered] ? '成功' : '失敗'}"
    puts "  ✅ ネストメール保護: #{@results[:nested_security][:nested_email_filtered] ? '成功' : '失敗'}"
    puts "  ✅ ネストパスワード保護: #{@results[:nested_security][:nested_password_filtered] ? '成功' : '失敗'}"
    puts "  ✅ データベースURL保護: #{@results[:nested_security][:database_url_filtered] ? '成功' : '失敗'}"
  end

  def test_performance_impact
    puts "\n⚡ テスト5: パフォーマンス影響測定"

    large_data = Array.new(100) do |i|
      {
        id: i,
        name: "Item #{i}",
        secret_key: "secret_#{i}_abcdefghijklmnop"
      }
    end

         performance_job_class = Class.new(ApplicationJob) do
       def perform(data)
         Rails.logger.info "Processing performance test data"
       end
     end
     Object.const_set('PerformanceTestJob', performance_job_class) unless defined?(PerformanceTestJob)

    start_time = Time.current
    capture_logs do
      PerformanceTestJob.perform_now(large_data)
    end
    end_time = Time.current

    processing_time = end_time - start_time
    log_content = @captured_logs.string

    @results[:performance] = {
      processing_time: processing_time.round(3),
      within_threshold: processing_time < 1.0,
      secrets_filtered: !log_content.include?('secret_0_abcdefghijklmnop')
    }

    puts "  ✅ 処理時間: #{@results[:performance][:processing_time]}秒"
    puts "  ✅ 性能閾値内: #{@results[:performance][:within_threshold] ? '1秒以内' : '閾値超過'}"
    puts "  ✅ 大量データでの機密情報保護: #{@results[:performance][:secrets_filtered] ? '成功' : '失敗'}"
  end

  def capture_logs
    @captured_logs.string = ""
    original_logger = Rails.logger
    Rails.logger = @test_logger

    yield

  ensure
    Rails.logger = original_logger
  end

  def create_test_admin
    # 既存の管理者を使用するか、簡単なオブジェクトを作成
    Admin.first || Class.new do
      def id; 1; end
      def email; 'test@example.com'; end
    end.new
  rescue => e
    puts "管理者取得エラー（デフォルト管理者を使用）: #{e.message}"
    Class.new do
      def id; 1; end
      def email; 'test@example.com'; end
    end.new
  end

  def display_results
    puts "\n" + "=" * 60
    puts "📊 **セキュリティ対策 動作確認結果**"
    puts "=" * 60

    all_tests_passed = true

    @results.each do |test_name, results|
      puts "\n🔍 #{test_name.to_s.humanize}:"
      results.each do |check, status|
        icon = status ? "✅" : "❌"
        puts "  #{icon} #{check.to_s.humanize}: #{status ? '成功' : '失敗'}"
        all_tests_passed = false unless status
      end
    end

    puts "\n" + "=" * 60
    if all_tests_passed
      puts "🎉 **全てのセキュリティテストが成功しました！**"
      puts "✅ ActiveJobの引数から機密情報が適切にフィルタリングされています"
      puts "✅ ログに平文の機密情報は出力されません"
    else
      puts "⚠️  **一部のテストで問題が検出されました**"
      puts "❌ セキュリティ設定の確認が必要です"
    end
    puts "=" * 60

    # ログサンプルの表示
    puts "\n📝 **キャプチャされたログサンプル** (最新100文字):"
    puts "-" * 40
    puts @captured_logs.string.split("\n").last(3).join("\n")[0..100] + "..."
    puts "-" * 40
  end
end

# テスト実行
if __FILE__ == $0
  verifier = SecurityVerificationTest.new
  verifier.run_all_tests
end
