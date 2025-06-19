# frozen_string_literal: true

# 店舗ログインUI動作確認タスク
# ============================================================================
# CLAUDE.md準拠: UIのJavaScript動作検証
#
# 用途:
# - 店舗ログイン画面の動作確認
# - 一時パスワードタブ切り替え検証
# - ルーティング設定確認
# ============================================================================

namespace :store_login do
  desc "Check store login UI routes and parameters"
  task check_routes: :environment do
    puts "🔍 店舗ログインUI確認"
    puts "=" * 50

    # 店舗データ確認
    store = Store.active.first
    if store.nil?
      puts "❌ アクティブな店舗が見つかりません"
      puts "rake db:seed を実行してテストデータを作成してください"
      exit 1
    end

    puts "✅ テスト店舗情報:"
    puts "  名前: #{store.name}"
    puts "  スラッグ: #{store.slug}"
    puts ""

    # ルーティング確認
    puts "📍 利用可能なURL:"
    puts "  1. 店舗選択画面:"
    puts "     http://localhost:3000/stores"
    puts ""
    puts "  2. 店舗ログイン画面（store_slug付き）:"
    puts "     http://localhost:3000/store/sign_in?store_slug=#{store.slug}"
    puts ""
    puts "  3. 一時パスワード関連エンドポイント:"

    # ルーティングヘルパー確認
    include Rails.application.routes.url_helpers

    begin
      puts "     送信: POST #{store_request_temp_password_path(store_slug: store.slug)}"
      puts "     検証: POST #{store_verify_temp_password_path(store_slug: store.slug)}"
    rescue => e
      puts "     ❌ ルーティングエラー: #{e.message}"
    end

    puts ""
    puts "🧪 JavaScript動作確認方法:"
    puts "  1. ブラウザで開発者ツールを開く（F12）"
    puts "  2. Consoleタブで以下のログを確認:"
    puts "     - 'Store login page loaded'"
    puts "     - 'Email auth tab clicked'"
    puts "     - 'Email auth form found: [URL]'"
    puts ""
    puts "⚠️  注意事項:"
    puts "  - store_slug パラメータが必須です"
    puts "  - パラメータがない場合、一時パスワード機能は使用できません"
  end

  desc "Simulate email auth request"
  task :test_email_request, [ :email ] => :environment do |_task, args|
    email = args[:email] || "test@example.com"
    store = Store.active.first

    unless store
      puts "❌ アクティブな店舗が見つかりません"
      exit 1
    end

    puts "🧪 一時パスワード送信シミュレーション"
    puts "=" * 50

    # StoreUserを検索または作成
    store_user = store.store_users.find_by(email: email)
    if store_user.nil?
      puts "⚠️  ユーザーが存在しません: #{email}"
      puts "新規作成しますか？ (y/n)"

      if $stdin.gets.chomp.downcase == "y"
        store_user = StoreUser.create!(
          store: store,
          name: "Test User",
          email: email,
          password: "Password123!",
          role: "staff"
        )
        puts "✅ ユーザー作成完了"
      else
        exit 0
      end
    end

    # EmailAuthService実行
    service = EmailAuthService.new
    result = service.generate_and_send_temp_password(
      store_user,
      request_metadata: {
        ip_address: "127.0.0.1",
        user_agent: "Test Script",
        requested_at: Time.current
      }
    )

    if result[:success]
      puts "✅ 一時パスワード送信成功"
      puts "  Temp Password ID: #{result[:temp_password_id]}"
      puts "  有効期限: #{result[:expires_at]}"
      puts ""
      puts "📧 メール確認:"
      puts "  http://localhost:8025"
    else
      puts "❌ 送信失敗: #{result[:error]}"
    end
  end
end
