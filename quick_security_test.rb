#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================
# StockRx セキュリティ対策 簡易動作確認
# ============================================

require_relative './config/environment'

puts "🔐 StockRx セキュリティ対策 動作確認"
puts "=" * 50

# 1. SecureArgumentSanitizerの動作確認
puts "\n📋 1. SecureArgumentSanitizer動作テスト"
test_data = {
  api_token: "test_api_key_12345",
  password: "super_secret_password",
  user_email: "user@company.internal",
  public_info: "this_is_safe_data"
}

result = SecureArgumentSanitizer.sanitize([ test_data ], "TestJob")
puts "  入力: #{test_data.inspect}"
puts "  出力: #{result.inspect}"

# 2. ApplicationJobのフィルタリング確認
puts "\n🔧 2. ApplicationJobフィルタリングテスト"
class QuickTestJob < ApplicationJob
  def perform(data)
    Rails.logger.info "Quick test job executed"
  end
end

# ログをキャプチャするためのStringIO
log_output = StringIO.new
temp_logger = Logger.new(log_output)

begin
  # 一時的にロガーを置換
  original_logger = Rails.logger
  Rails.logger = temp_logger

  # テストジョブ実行
  QuickTestJob.perform_now(test_data)

  # ログ内容を確認
  logs = log_output.string
  if logs.include?('[FILTERED]')
    puts "  ✅ フィルタリング成功: ログに[FILTERED]が含まれています"
  else
    puts "  ⚠️ フィルタリング確認: ログ内容を詳細確認が必要"
  end

ensure
  Rails.logger = original_logger
end

# 3. パフォーマンステスト
puts "\n⚡ 3. パフォーマンステスト"
start_time = Time.current

1000.times do
  SecureArgumentSanitizer.sanitize([ test_data ], "TestJob")
end

duration = Time.current - start_time
puts "  1000回実行時間: #{(duration * 1000).round(2)}ms"
puts "  平均処理時間: #{(duration * 1000 / 1000).round(4)}ms/回"

if duration < 0.1
  puts "  ✅ パフォーマンス良好"
else
  puts "  ⚠️ パフォーマンス要改善"
end

# 4. エラーハンドリングテスト
puts "\n🛡️ 4. エラーハンドリングテスト"
begin
  # 意図的に問題のあるデータでテスト
  broken_data = Class.new do
    def inspect
      raise "Intentional error for testing"
    end
  end.new

  result = SecureArgumentSanitizer.sanitize([ broken_data ], "TestJob")
  puts "  ✅ エラーハンドリング成功: #{result.inspect}"
rescue => e
  puts "  ⚠️ エラーハンドリング要改善: #{e.message}"
end

# 5. 設定確認
puts "\n⚙️ 5. 設定確認"
config = Rails.application.config.secure_job_logging
if config&.dig(:enabled)
  puts "  ✅ セキュアロギング有効"
  puts "  デバッグモード: #{config[:debug_mode] ? '有効' : '無効'}"
  puts "  厳格モード: #{config[:strict_mode] ? '有効' : '無効'}"
else
  puts "  ⚠️ セキュアロギング無効"
end

puts "\n" + "=" * 50
puts "🎯 **総合評価**"

success_count = 0
total_tests = 5

# 評価ロジック
success_count += 1 if result.first[:api_token] == '[FILTERED]'
success_count += 1 if result.first[:password] == '[FILTERED]'
success_count += 1 if duration < 0.1
success_count += 1 if config&.dig(:enabled)
success_count += 1 if defined?(SecureArgumentSanitizer)

score = (success_count.to_f / total_tests * 100).round

puts "セキュリティスコア: #{score}%"

if score >= 80
  puts "🎉 **優秀**: セキュリティ対策が適切に機能しています"
elsif score >= 60
  puts "✅ **良好**: 基本的なセキュリティは確保されています"
else
  puts "⚠️ **要改善**: セキュリティ設定の見直しが必要です"
end

puts "\n📚 詳細確認方法:"
puts "  - ログ確認: docker compose exec web cat log/development.log"
puts "  - テスト実行: docker compose exec web rspec spec/jobs/"
puts "  - 設定確認: cat config/environments/development.rb | grep secure"
