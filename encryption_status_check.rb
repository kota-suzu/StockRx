#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================
# StockRx 暗号化状況確認スクリプト
# ============================================

require_relative './config/environment'

puts "🔐 StockRx 暗号化状況確認"
puts "=" * 60

# 1. 現在のセキュリティ方式の確認
puts "\n📋 1. 現在のセキュリティ方式分析"

test_data = {
  api_token: "test_api_key_12345",
  password: "super_secret_password",
  user_email: "user@company.internal",
  credit_card: "4111-1111-1111-1111"
}

# SecureArgumentSanitizerの動作確認
result = SecureArgumentSanitizer.sanitize([ test_data ], "TestJob")
puts "  📤 元データ: #{test_data.inspect}"
puts "  📥 処理後: #{result.inspect}"

# 2. 暗号化vs.フィルタリングの判定
puts "\n🔍 2. セキュリティ方式の判定"

is_encrypted = false
is_filtered = false

result.first.each do |key, value|
  if value.to_s.include?("[FILTERED]")
    is_filtered = true
    puts "  🔒 #{key}: フィルタリング方式 (#{value})"
  elsif value.to_s.length > 20 && value.to_s.match?(/^[A-Za-z0-9+\/=]+$/)
    is_encrypted = true
    puts "  🔐 #{key}: 暗号化の可能性 (#{value[0..20]}...)"
  else
    puts "  ✅ #{key}: 平文 (#{value})"
  end
end

# 3. Rails暗号化機能の確認
puts "\n🛡️ 3. Rails暗号化機能の確認"

# Rails暗号化キーの確認（Rails 6+対応）
secret_key_base = Rails.application.secret_key_base
if secret_key_base.present?
  puts "  ✅ secret_key_base: 設定済み (#{secret_key_base[0..20]}...)"
else
  puts "  ❌ secret_key_base: 未設定"
end

# Rails credentialsの確認（Rails 5.2+）
begin
  if defined?(Rails.application.credentials) && Rails.application.credentials.secret_key_base.present?
    puts "  ✅ credentials.secret_key_base: 設定済み"
  else
    puts "  ⚠️ credentials.secret_key_base: 未設定（ENV['SECRET_KEY_BASE']を使用）"
  end
rescue => e
  puts "  ⚠️ credentials確認エラー: #{e.message}"
end

# Active Supportの暗号化機能の確認
puts "\n🔧 4. Active Support暗号化機能テスト"

begin
  # ActiveSupport::MessageEncryptorのテスト
  secret = Rails.application.secret_key_base
  if secret
    key = ActiveSupport::KeyGenerator.new(secret).generate_key("test", 32)
    encryptor = ActiveSupport::MessageEncryptor.new(key)

    test_message = "sensitive_data_123"
    encrypted = encryptor.encrypt_and_sign(test_message)
    decrypted = encryptor.decrypt_and_verify(encrypted)

    puts "  📤 元データ: #{test_message}"
    puts "  🔐 暗号化: #{encrypted[0..50]}..."
    puts "  📥 復号化: #{decrypted}"
    puts "  ✅ Rails暗号化: 正常動作"

    encryption_available = true
  else
    puts "  ❌ Rails暗号化: secret_key_baseが必要"
    encryption_available = false
  end
rescue => e
  puts "  ❌ Rails暗号化エラー: #{e.message}"
  encryption_available = false
end

# 5. データベース暗号化の確認
puts "\n💾 5. データベース暗号化の確認"

# Active Record Encryptionの確認（Rails 7+）
if defined?(ActiveRecord::Encryption)
  puts "  ✅ Active Record Encryption: 利用可能"

  # 設定確認（エラーハンドリング付き）
  begin
    if ActiveRecord::Encryption.config.primary_key.present?
      puts "  ✅ 暗号化プライマリキー: 設定済み"
    else
      puts "  ⚠️ 暗号化プライマリキー: 未設定"
    end
  rescue ActiveRecord::Encryption::Errors::Configuration => e
    puts "  ⚠️ 暗号化設定エラー: #{e.message}"
    puts "  📋 対応: rails credentials:edit で active_record_encryption.primary_key を設定"
  rescue => e
    puts "  ❌ 暗号化確認エラー: #{e.message}"
  end
else
  puts "  ❌ Active Record Encryption: 利用不可（Rails 7.0+ が必要）"
end

# 6. 環境変数暗号化の確認
puts "\n🌍 6. 環境変数暗号化の確認"

sensitive_env_vars = %w[
  DATABASE_PASSWORD
  REDIS_PASSWORD
  SECRET_KEY_BASE
  STRIPE_SECRET_KEY
  AWS_SECRET_ACCESS_KEY
]

sensitive_env_vars.each do |var|
  value = ENV[var]
  if value.present?
    if value.length > 20 && value.match?(/^[A-Za-z0-9+\/=]+$/)
      puts "  🔐 #{var}: 暗号化済みの可能性 (#{value[0..10]}...)"
    else
      puts "  ⚠️ #{var}: 平文 (#{value[0..10]}...)"
    end
  else
    puts "  ❌ #{var}: 未設定"
  end
end

# 7. 総合評価
puts "\n" + "=" * 60
puts "📊 **暗号化状況の総合評価**"
puts "=" * 60

security_score = 0
max_score = 100

# スコア計算
security_score += 30 if is_filtered
security_score += 40 if encryption_available
security_score += 20 if defined?(ActiveRecord::Encryption)
security_score += 10 if Rails.application.secret_key_base.present?

puts "\n🏆 セキュリティスコア: #{security_score}/#{max_score}"

# 方式の判定
if is_encrypted && encryption_available
  puts "🔐 **暗号化方式**: データは暗号化されて保護されています"
  security_level = "高度"
elsif is_filtered && encryption_available
  puts "🔒 **フィルタリング + 暗号化準備完了**: 現在はフィルタリング、暗号化も実装可能"
  security_level = "中級〜高級"
elsif is_filtered
  puts "🔍 **フィルタリング方式**: データはマスキングされて保護されています"
  security_level = "基本〜中級"
else
  puts "⚠️ **保護不十分**: 追加のセキュリティ対策が必要です"
  security_level = "要改善"
end

# 推奨事項
puts "\n📋 **推奨改善事項**:"

if security_score < 70
  puts "  🚨 優先度高:"
  puts "    - 暗号化機能の実装"
  puts "    - secret_key_baseの設定"
  puts "    - 環境変数の暗号化"
end

if security_score < 90
  puts "  ⚠️ 推奨:"
  puts "    - Active Record Encryptionの設定"
  puts "    - データベースレベルでの暗号化"
  puts "    - ログローテーションと暗号化保存"
end

puts "    - 定期的なセキュリティ監査"
puts "    - 暗号化キーのローテーション"

# 8. 暗号化実装の提案
if security_score < 80
  puts "\n🛠️ **暗号化実装の提案**"
  puts "実行方法: docker compose exec web ruby implement_encryption.rb"
end

puts "\n" + "=" * 60
