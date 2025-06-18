# frozen_string_literal: true

# EmailAuth（一時パスワード認証）テストタスク
# ============================================================================
# CLAUDE.md準拠: 開発環境でのメール送信テスト
# 
# 用途:
# - EmailAuthServiceの動作確認
# - StoreAuthMailerの送信テスト
# - MailHogまたはLetter Opener Webでのメール確認
# 
# 実行方法:
# - rake email_auth:test_basic                    # 基本テスト
# - rake email_auth:test_full                     # 包括テスト
# - rake email_auth:test_with_store[store_slug]   # 特定店舗テスト
# ============================================================================

namespace :email_auth do
  desc "Basic email authentication test - 基本的なメール認証テスト"
  task test_basic: :environment do
    puts "🧪 EmailAuth基本テスト開始"
    puts "=" * 50
    
    # テストデータ準備
    store = Store.active.first
    if store.nil?
      puts "❌ エラー: アクティブな店舗が見つかりません"
      puts "まず店舗データを作成してください: rake db:seed"
      exit 1
    end
    
    store_user = store.store_users.first
    if store_user.nil?
      puts "❌ エラー: 店舗ユーザーが見つかりません"
      puts "店舗ユーザーを作成中..."
      store_user = StoreUser.create!(
        store: store,
        name: "テストユーザー",
        email: "test@#{store.slug}.example.com",
        password: "Password123!",
        role: "staff"
      )
      puts "✅ テストユーザー作成完了: #{store_user.email}"
    end
    
    puts "📋 テスト環境情報:"
    puts "  Store: #{store.name} (#{store.slug})"
    puts "  User: #{store_user.name} (#{store_user.email})"
    puts "  Mail Method: #{ActionMailer::Base.delivery_method}"
    puts ""
    
    # EmailAuthServiceテスト
    puts "🔧 EmailAuthService テスト開始"
    service = EmailAuthService.new
    
    result = service.generate_and_send_temp_password(
      store_user,
      admin_id: nil,
      request_metadata: {
        ip_address: "127.0.0.1",
        user_agent: "EmailAuth Test Script",
        requested_at: Time.current
      }
    )
    
    if result[:success]
      puts "✅ 一時パスワード生成・送信成功"
      if result[:temp_password_id]
        puts "  Temp Password ID: #{result[:temp_password_id]}"
      end
      if result[:expires_at]
        puts "  Expires At: #{result[:expires_at]}"
      end
      if result[:delivery_result]
        puts "  Delivery Result: #{result[:delivery_result].class.name}"
      end
      
      if ActionMailer::Base.delivery_method == :letter_opener
        puts ""
        puts "📧 Letter Opener Web でメールを確認:"
        puts "  URL: http://localhost:3000/letter_opener"
      elsif ActionMailer::Base.delivery_method == :smtp
        puts ""
        puts "📧 MailHog Web UI でメールを確認:"
        puts "  URL: http://localhost:8025"
      end
      
    else
      puts "❌ 一時パスワード生成・送信失敗"
      puts "  エラー: #{result[:error]}"
      exit 1
    end
    
    puts ""
    puts "🧪 基本テスト完了"
  end
  
  desc "Full email authentication test - 包括的なメール認証テスト"
  task test_full: :environment do
    puts "🧪 EmailAuth包括テスト開始"
    puts "=" * 50
    
    # 複数店舗・複数ユーザーでのテスト
    stores = Store.active.limit(2)
    
    stores.each do |store|
      puts "🏪 店舗: #{store.name}"
      
      store_user = store.store_users.first
      next unless store_user
      
      service = EmailAuthService.new
      
      # レート制限テスト
      puts "  📊 レート制限テスト実行中..."
      3.times do |i|
        result = service.generate_and_send_temp_password(
          store_user,
          request_metadata: {
            ip_address: "127.0.0.1",
            user_agent: "Rate Limit Test #{i + 1}",
            requested_at: Time.current
          }
        )
        
        if result[:success]
          puts "    ✅ 送信 #{i + 1}: 成功"
        else
          puts "    ⚠️  送信 #{i + 1}: #{result[:error]}"
        end
        
        sleep 1 # レート制限間隔
      end
      
      puts ""
    end
    
    puts "🧪 包括テスト完了"
  end
  
  desc "Test with specific store - 特定店舗でのテスト"
  task :test_with_store, [:store_slug] => :environment do |_task, args|
    store_slug = args[:store_slug]
    
    if store_slug.blank?
      puts "❌ 店舗スラッグを指定してください"
      puts "使用方法: rake email_auth:test_with_store[store_slug]"
      exit 1
    end
    
    store = Store.active.find_by(slug: store_slug)
    if store.nil?
      puts "❌ 店舗が見つかりません: #{store_slug}"
      puts "利用可能な店舗:"
      Store.active.pluck(:slug, :name).each do |slug, name|
        puts "  - #{slug}: #{name}"
      end
      exit 1
    end
    
    puts "🧪 特定店舗テスト: #{store.name}"
    puts "=" * 50
    
    # 該当店舗のすべてのユーザーでテスト
    store.store_users.each do |store_user|
      puts "👤 ユーザー: #{store_user.name} (#{store_user.email})"
      
      service = EmailAuthService.new
      result = service.generate_and_send_temp_password(
        store_user,
        request_metadata: {
          ip_address: "192.168.1.100",
          user_agent: "Store Specific Test",
          requested_at: Time.current
        }
      )
      
      if result[:success]
        puts "  ✅ 送信成功: #{result[:temp_password].id}"
      else
        puts "  ❌ 送信失敗: #{result[:error]}"
      end
      
      puts ""
    end
    
    puts "🧪 特定店舗テスト完了"
  end
  
  desc "Cleanup expired temp passwords - 期限切れ一時パスワードのクリーンアップ"
  task cleanup: :environment do
    puts "🧹 期限切れ一時パスワードクリーンアップ開始"
    
    expired_count = TempPassword.expired.count
    puts "期限切れ一時パスワード数: #{expired_count}"
    
    if expired_count > 0
      TempPassword.expired.delete_all
      puts "✅ #{expired_count}件の期限切れ一時パスワードを削除しました"
    else
      puts "✅ 期限切れ一時パスワードはありません"
    end
  end
  
  desc "Show mail configuration - メール設定確認"
  task show_config: :environment do
    puts "📧 メール設定確認"
    puts "=" * 50
    
    puts "Delivery Method: #{ActionMailer::Base.delivery_method}"
    puts "Default URL Options: #{ActionMailer::Base.default_url_options}"
    
    if ActionMailer::Base.delivery_method == :smtp
      puts "SMTP Settings:"
      ActionMailer::Base.smtp_settings.each do |key, value|
        # パスワード等の機密情報をマスク
        display_value = key.to_s.include?('password') ? '[MASKED]' : value
        puts "  #{key}: #{display_value}"
      end
    end
    
    puts ""
    puts "Letter Opener Web: http://localhost:3000/letter_opener"
    puts "MailHog Web UI: http://localhost:8025"
  end
end

# ============================================
# TODO: Phase 2以降の拡張予定
# ============================================
# 1. 🟡 パフォーマンステスト
#    - 大量メール送信テスト
#    - 並行送信テスト
#    - メモリ使用量測定
#
# 2. 🟢 統合テスト
#    - EmailAuthController連携テスト
#    - フロントエンド統合テスト
#    - E2Eテストシナリオ
#
# 3. 🟢 監査・レポート機能
#    - 送信履歴レポート
#    - エラー分析レポート
#    - セキュリティ監査ログ