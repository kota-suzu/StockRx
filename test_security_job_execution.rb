# frozen_string_literal: true

# ============================================================================
# StockRx セキュリティフィルタリング動作確認スクリプト
# ============================================================================
# 使用方法: Railsコンソールで以下を実行
#   load "test_security_job_execution.rb"
#   SecurityJobTest.run_all_tests
#
# 目的: ActiveJobのセキュリティフィルタリングが正常に動作することを確認
# ============================================================================

class SecurityJobTest
  class << self
    # ============================================================================
    # メインテスト実行
    # ============================================================================
    
    def run_all_tests
      puts "🔐 StockRx セキュリティフィルタリング動作確認開始"
      puts "=" * 60
      
      # ログファイルサイズを記録（before）
      log_size_before = File.size("log/development.log") rescue 0
      
      puts "📋 テスト実行前のログサイズ: #{format_file_size(log_size_before)}"
      puts ""
      
      # 各テストケース実行
      test_cases = [
        :test_api_keys,
        :test_personal_information,
        :test_business_secrets,
        :test_nested_data_structures,
        :test_large_data_payload,
        :test_mixed_sensitive_data
      ]
      
      results = []
      
      test_cases.each_with_index do |test_method, index|
        puts "🧪 テスト #{index + 1}/#{test_cases.size}: #{test_method}"
        
        begin
          result = send(test_method)
          results << { test: test_method, status: :success, result: result }
          puts "   ✅ 成功"
        rescue => e
          results << { test: test_method, status: :error, error: e.message }
          puts "   ❌ エラー: #{e.message}"
        end
        
        puts ""
        sleep 1 # ログの分離のため少し待機
      end
      
      # ログファイルサイズを記録（after）
      log_size_after = File.size("log/development.log") rescue 0
      log_increase = log_size_after - log_size_before
      
      puts "=" * 60
      puts "📋 テスト結果サマリー"
      puts "=" * 60
      puts "📝 実行前ログサイズ: #{format_file_size(log_size_before)}"
      puts "📝 実行後ログサイズ: #{format_file_size(log_size_after)}" 
      puts "📈 ログ増加サイズ: #{format_file_size(log_increase)}"
      puts ""
      
      success_count = results.count { |r| r[:status] == :success }
      error_count = results.count { |r| r[:status] == :error }
      
      puts "✅ 成功: #{success_count}/#{results.size}"
      puts "❌ エラー: #{error_count}/#{results.size}" if error_count > 0
      puts ""
      
      # エラー詳細
      if error_count > 0
        puts "🚨 エラー詳細:"
        results.select { |r| r[:status] == :error }.each do |result|
          puts "   - #{result[:test]}: #{result[:error]}"
        end
        puts ""
      end
      
      puts "🔍 実際のログ確認方法:"
      puts "   tail -50 log/development.log | grep -E '\\[(FILTERED|SecureJobLogging)\\]'"
      puts ""
      puts "📊 詳細ログ解析:"
      puts "   ruby verify_job_logs.rb"
      
      results
    end
    
    # ============================================================================
    # 個別テストケース
    # ============================================================================
    
    def test_api_keys
      puts "   🔑 APIキー・認証情報のフィルタリングテスト"
      
      sensitive_data = {
        stripe_secret_key: "test_key_51234567890abcdefghijklmnop",
        stripe_public_key: "pk_test_51234567890abcdefghijklmnop", 
        github_token: "ghp_1234567890abcdefghijklmnopqrstuvwxyz",
        aws_access_key: "AKIAIOSFODNN7EXAMPLE",
        webhook_secret: "whsec_1234567890abcdefghijklmnop",
        api_endpoint: "https://api.example.com/v1/payments",
        client_secret: "cs_test_1234567890abcdefghijklmnop"
      }
      
      execute_test_job("APIキーテスト", sensitive_data)
    end
    
    def test_personal_information
      puts "   👤 個人情報のフィルタリングテスト"
      
      personal_data = {
        user_email: "john.doe@example.com",
        admin_email: "admin@stockrx.com",
        phone_number: "090-1234-5678",
        social_security: "123-45-6789",
        credit_card: "4111-1111-1111-1111",
        bank_account: "1234567890",
        full_name: "田中太郎",
        address: "東京都渋谷区1-2-3"
      }
      
      execute_test_job("個人情報テスト", personal_data)
    end
    
    def test_business_secrets
      puts "   💼 ビジネス機密情報のフィルタリングテスト"
      
      business_data = {
        password: "super_secret_password_123",
        database_password: "mysql_secret_pwd_456",
        encryption_key: "encryption_key_789abcdef",
        salary_data: { employee_id: 123, salary: 5000000 },
        revenue_report: { monthly_revenue: 10000000, profit_margin: 0.25 },
        pricing_strategy: { discount_rate: 0.15, special_price: 999999 },
        confidential_notes: "極秘プロジェクト情報"
      }
      
      execute_test_job("ビジネス機密テスト", business_data)
    end
    
    def test_nested_data_structures
      puts "   🔗 ネストしたデータ構造のフィルタリングテスト"
      
      nested_data = {
        user: {
          profile: {
            email: "nested.user@example.com",
            credentials: {
              password: "nested_password_123",
              api_key: "sk_nested_1234567890"
            }
          },
          settings: {
            notifications: {
              email_token: "email_token_abcdef123",
              webhook_url: "https://webhook.example.com/secret"
            }
          }
        },
        payment: {
          methods: [
            { type: "stripe", secret_key: "test_nested_payment" },
            { type: "paypal", client_secret: "paypal_nested_secret" }
          ]
        }
      }
      
      execute_test_job("ネストデータテスト", nested_data)
    end
    
    def test_large_data_payload
      puts "   📦 大容量データのフィルタリングテスト"
      
      # 大きなCSVデータを模擬
      csv_content = (1..100).map do |i|
        "#{i},product_#{i},admin_#{i}@stockrx.com,test_large_data_#{i},#{rand(1000..9999)}"
      end.join("\n")
      
      large_data = {
        csv_import_data: csv_content,
        file_metadata: {
          filename: "sensitive_inventory_data.csv",
          uploader_email: "admin@stockrx.com",
          api_key: "test_csv_import_12345",
          file_size: csv_content.bytesize
        },
        processing_options: {
          encryption_enabled: true,
          notification_webhook: "https://webhook.stockrx.com/csv-complete",
          admin_notifications: ["admin1@stockrx.com", "admin2@stockrx.com"]
        }
      }
      
      execute_test_job("大容量データテスト", large_data)
    end
    
    def test_mixed_sensitive_data
      puts "   🎭 混合機密データのフィルタリングテスト"
      
      mixed_data = [
        "test_mixed_api_key_123",
        { password: "mixed_password_456", user_email: "mixed@example.com" },
        ["normal_data", "secret_token_789", "public_info"],
        {
          normal_field: "public_value",
          hidden_secrets: {
            api_credentials: "sk_hidden_secret_abc",
            user_data: {
              email: "hidden.user@example.com",
              auth_token: "auth_hidden_xyz"
            }
          }
        }
      ]
      
      execute_test_job("混合データテスト", mixed_data)
    end
    
    private
    
    # ============================================================================
    # ヘルパーメソッド
    # ============================================================================
    
    def execute_test_job(test_name, job_args)
      puts "     📤 ジョブ実行: #{test_name}"
      
      # ジョブ実行の詳細ログを有効化
      original_log_level = Rails.logger.level
      Rails.logger.level = :debug
      
      begin
        # ApplicationJobを適切にperform_nowで実行
        result = ApplicationJob.perform_now(job_args)
        puts "     ✅ ジョブ実行完了"
        
        # 実行結果の概要
        {
          test_name: test_name,
          job_class: "ApplicationJob",
          arguments_processed: result.is_a?(Array) ? result.size : 1,
          execution_time: Time.current
        }
        
      rescue => e
        puts "     ❌ ジョブ実行エラー: #{e.message}"
        raise e
      ensure
        Rails.logger.level = original_log_level
      end
    end
    
    def format_file_size(size_bytes)
      return "0 B" if size_bytes == 0
      
      units = %w[B KB MB GB]
      index = 0
      size = size_bytes.to_f
      
      while size >= 1024 && index < units.length - 1
        size /= 1024
        index += 1
      end
      
      "#{size.round(2)} #{units[index]}"
    end
  end
end

# ============================================================================
# 単体テスト実行用ヘルパー
# ============================================================================

def quick_security_test
  SecurityJobTest.test_api_keys
end

def quick_personal_test  
  SecurityJobTest.test_personal_information
end

def quick_business_test
  SecurityJobTest.test_business_secrets
end

# ============================================================================
# 使用方法表示
# ============================================================================

puts "🔐 StockRx セキュリティテストスクリプト読み込み完了"
puts ""
puts "📋 使用方法:"
puts "  SecurityJobTest.run_all_tests    # 全テスト実行"  
puts "  quick_security_test              # APIキーテストのみ"
puts "  quick_personal_test              # 個人情報テストのみ"
puts "  quick_business_test              # ビジネス機密テストのみ"
puts ""
puts "🔍 ログ確認方法:"
puts "  tail -f log/development.log | grep -E '\\[(FILTERED|SecureJobLogging)\\]'"
puts "" 