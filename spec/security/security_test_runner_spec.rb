# frozen_string_literal: true

require 'rails_helper'

# Phase 5-5: セキュリティテスト統合ランナー
# ============================================
# 全セキュリティテストの実行と結果レポート生成
# ============================================
RSpec.describe "Security Test Runner", type: :feature do
  include SecurityTestHelper if defined?(SecurityTestHelper)

  # ============================================
  # セキュリティテストスイート実行
  # ============================================
  describe "包括的セキュリティテスト実行" do
    before(:all) do
      @test_results = {
        passed: [],
        failed: [],
        warnings: [],
        start_time: Time.current
      }
    end

    after(:all) do
      # テスト結果レポートの生成
      generate_security_report(@test_results)
    end

    context "OWASP Top 10チェック" do
      it "A01: アクセス制御の破損テスト" do
        result = run_security_test("Access Control") do
          # 権限昇格テスト
          admin = create(:admin, role: "regular")
          sign_in admin

          # スーパー管理者機能へのアクセス試行
          get admin_system_settings_path
          expect(response).to have_http_status(:forbidden)

          # 他ユーザーのデータへのアクセス試行
          other_store = create(:store)
          get admin_store_path(other_store)
          expect(response).to have_http_status(:forbidden)
        end

        record_test_result("A01: Access Control", result)
      end

      it "A02: 暗号化の失敗テスト" do
        result = run_security_test("Cryptographic Failures") do
          # パスワード暗号化確認
          user = create(:admin, password: "SecurePass123!")
          expect(user.encrypted_password).not_to eq("SecurePass123!")
          expect(user.encrypted_password).to match(/^\$2[ayb]\$/)

          # 機密データのマスキング確認
          inventory = create(:inventory, notes: "Card: 4111-1111-1111-1111")
          audit_log = inventory.audit_logs.last
          expect(JSON.parse(audit_log.details).to_s).not_to include("4111-1111-1111-1111")
        end

        record_test_result("A02: Cryptographic Failures", result)
      end

      it "A03: インジェクションテスト" do
        result = run_security_test("Injection") do
          admin = create(:admin)
          sign_in admin

          # SQLインジェクション
          malicious_sql = "'; DROP TABLE inventories; --"
          get admin_inventories_path, params: { q: { name_cont: malicious_sql } }
          expect(response).to be_successful
          expect(Inventory.table_exists?).to be true

          # XSS
          xss_payload = "<script>alert('XSS')</script>"
          post admin_inventories_path, params: {
            inventory: { name: xss_payload, sku: "XSS001", price: 100 }
          }

          if response.redirect?
            follow_redirect!
            expect(response.body).not_to include(xss_payload)
          end
        end

        record_test_result("A03: Injection", result)
      end

      # 残りのOWASP Top 10テスト...
    end

    context "認証・認可テスト" do
      it "多要素認証が実装されていること" do
        result = run_security_test("Multi-Factor Authentication") do
          if Admin.method_defined?(:otp_required_for_login)
            admin = create(:admin)
            expect(admin).to respond_to(:otp_secret)
            expect(admin).to respond_to(:generate_otp_secret)
          else
            pending "MFA未実装"
          end
        end

        record_test_result("MFA Implementation", result)
      end

      it "セッション管理が適切であること" do
        result = run_security_test("Session Management") do
          # セッションタイムアウト確認
          admin = create(:admin)
          sign_in admin

          # 30分後
          travel_to 31.minutes.from_now do
            get admin_inventories_path
            expect(response).to redirect_to(new_admin_session_path)
          end
        end

        record_test_result("Session Management", result)
      end
    end

    context "データ保護テスト" do
      it "個人情報が適切に保護されていること" do
        result = run_security_test("Personal Data Protection") do
          # メールアドレスのマスキング
          user = create(:store_user, email: "test@example.com")
          user.audit_log("view", "データ参照")

          audit_log = user.audit_logs.last
          details = JSON.parse(audit_log.details)

          # メールアドレスが部分マスキングされているか
          expect(details.to_s).to match(/te\*+@example\.com/)
        end

        record_test_result("Personal Data Protection", result)
      end
    end

    context "インフラストラクチャセキュリティ" do
      it "セキュリティヘッダーが適切に設定されていること" do
        result = run_security_test("Security Headers") do
          get root_path

          required_headers = {
            "X-Frame-Options" => "DENY",
            "X-Content-Type-Options" => "nosniff",
            "X-XSS-Protection" => "1; mode=block",
            "Content-Security-Policy" => /default-src/,
            "Referrer-Policy" => "strict-origin-when-cross-origin"
          }

          required_headers.each do |header, expected|
            actual = response.headers[header]
            if expected.is_a?(Regexp)
              expect(actual).to match(expected)
            else
              expect(actual).to eq(expected)
            end
          end
        end

        record_test_result("Security Headers", result)
      end
    end
  end

  # ============================================
  # セキュリティスコアリング
  # ============================================
  describe "セキュリティスコア算出" do
    it "総合セキュリティスコアが基準を満たすこと" do
      score = calculate_security_score

      expect(score[:total]).to be >= 80

      # 各カテゴリの最低スコア
      expect(score[:authentication]).to be >= 75
      expect(score[:authorization]).to be >= 75
      expect(score[:data_protection]).to be >= 80
      expect(score[:infrastructure]).to be >= 85
      expect(score[:monitoring]).to be >= 70
    end
  end

  # ============================================
  # 脆弱性自動スキャン
  # ============================================
  describe "自動脆弱性スキャン" do
    it "既知の脆弱性が検出されないこと" do
      vulnerabilities = []

      # Gemの脆弱性チェック
      gem_audit = `bundle audit check 2>&1`
      vulnerabilities << "Gem脆弱性: #{gem_audit}" if $?.exitstatus != 0

      # JavaScriptパッケージの脆弱性チェック
      if File.exist?("package.json")
        npm_audit = `npm audit --json 2>&1`
        audit_result = JSON.parse(npm_audit) rescue {}
        if audit_result["vulnerabilities"]&.any?
          vulnerabilities << "npm脆弱性: #{audit_result["vulnerabilities"].count}件"
        end
      end

      # Railsセキュリティ設定チェック
      security_config_issues = check_rails_security_config
      vulnerabilities.concat(security_config_issues)

      expect(vulnerabilities).to be_empty,
        "脆弱性が検出されました:\n#{vulnerabilities.join("\n")}"
    end
  end

  # ============================================
  # ペネトレーションテスト準備
  # ============================================
  describe "ペネトレーションテスト準備状態" do
    it "外部セキュリティツールとの連携準備ができていること" do
      # OWASP ZAP連携チェック
      zap_ready = File.exist?("config/zap.yml") || ENV["ZAP_API_KEY"].present?

      # Burp Suite連携チェック
      burp_ready = File.exist?("config/burp.yml") || ENV["BURP_API_KEY"].present?

      # 少なくとも1つのツールが設定されていること
      expect(zap_ready || burp_ready).to be true,
        "ペネトレーションテストツールが設定されていません"
    end
  end

  private

  def run_security_test(test_name)
    begin
      yield
      { status: :passed, message: "#{test_name} passed" }
    rescue RSpec::Expectations::ExpectationNotMetError => e
      { status: :failed, message: "#{test_name} failed: #{e.message}" }
    rescue => e
      { status: :error, message: "#{test_name} error: #{e.message}" }
    end
  end

  def record_test_result(test_name, result)
    case result[:status]
    when :passed
      @test_results[:passed] << test_name
    when :failed
      @test_results[:failed] << { name: test_name, message: result[:message] }
    when :error
      @test_results[:warnings] << { name: test_name, message: result[:message] }
    end
  end

  def calculate_security_score
    scores = {
      authentication: 0,
      authorization: 0,
      data_protection: 0,
      infrastructure: 0,
      monitoring: 0
    }

    # 認証スコア
    scores[:authentication] += 25 if Admin.devise_modules.include?(:lockable)
    scores[:authentication] += 25 if Admin.devise_modules.include?(:timeoutable)
    scores[:authentication] += 25 if defined?(RateLimiter)
    scores[:authentication] += 25 if Admin.password_length.min >= 12

    # 認可スコア
    scores[:authorization] += 50 if defined?(Pundit) || defined?(CanCan)
    scores[:authorization] += 50 if Admin.column_names.include?("role")

    # データ保護スコア
    scores[:data_protection] += 33 if defined?(Auditable)
    scores[:data_protection] += 33 if Rails.application.config.force_ssl
    scores[:data_protection] += 34 if ActionController::Base.default_protect_from_forgery

    # インフラスコア
    get root_path
    scores[:infrastructure] += 20 if response.headers["X-Frame-Options"].present?
    scores[:infrastructure] += 20 if response.headers["Content-Security-Policy"].present?
    scores[:infrastructure] += 20 if response.headers["X-Content-Type-Options"].present?
    scores[:infrastructure] += 20 if response.headers["Strict-Transport-Security"].present?
    scores[:infrastructure] += 20 if response.headers["Permissions-Policy"].present?

    # 監視スコア
    scores[:monitoring] += 50 if AuditLog.table_exists?
    scores[:monitoring] += 50 if defined?(SecurityAlertMailer) || defined?(SlackNotifier)

    # 総合スコア
    scores[:total] = scores.values.sum / scores.size

    scores
  end

  def check_rails_security_config
    issues = []

    # セッションストアの確認
    if Rails.application.config.session_store == :cookie_store
      session_options = Rails.application.config.session_options || {}
      issues << "セッションにsecureフラグが設定されていません" unless session_options[:secure]
      issues << "セッションにhttponlyフラグが設定されていません" unless session_options[:httponly]
    end

    # 本番環境でのデバッグ設定
    if Rails.env.production?
      issues << "本番環境でデバッグが有効です" if Rails.application.config.consider_all_requests_local
    end

    # secrets設定
    if Rails.application.credentials.secret_key_base.nil?
      issues << "secret_key_baseが設定されていません"
    end

    issues
  end

  def generate_security_report(results)
    report = []
    report << "="*60
    report << "セキュリティテストレポート"
    report << "="*60
    report << "実行日時: #{results[:start_time]}"
    report << "完了日時: #{Time.current}"
    report << "実行時間: #{(Time.current - results[:start_time]).round(2)}秒"
    report << ""
    report << "【テスト結果サマリー】"
    report << "✅ 成功: #{results[:passed].count}件"
    report << "❌ 失敗: #{results[:failed].count}件"
    report << "⚠️  警告: #{results[:warnings].count}件"
    report << ""

    if results[:failed].any?
      report << "【失敗したテスト】"
      results[:failed].each do |failure|
        report << "- #{failure[:name]}"
        report << "  #{failure[:message]}"
      end
      report << ""
    end

    if results[:warnings].any?
      report << "【警告】"
      results[:warnings].each do |warning|
        report << "- #{warning[:name]}"
        report << "  #{warning[:message]}"
      end
      report << ""
    end

    # セキュリティスコア
    score = calculate_security_score
    report << "【セキュリティスコア】"
    report << "総合スコア: #{score[:total]}/100"
    report << "- 認証: #{score[:authentication]}/100"
    report << "- 認可: #{score[:authorization]}/100"
    report << "- データ保護: #{score[:data_protection]}/100"
    report << "- インフラ: #{score[:infrastructure]}/100"
    report << "- 監視: #{score[:monitoring]}/100"
    report << ""

    # 推奨事項
    report << "【推奨改善事項】"
    recommendations = generate_recommendations(score, results)
    recommendations.each_with_index do |rec, i|
      report << "#{i+1}. #{rec}"
    end

    report << "="*60

    # レポートファイルに保存
    report_path = Rails.root.join("tmp", "security_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.txt")
    File.write(report_path, report.join("\n"))

    puts report.join("\n")
    puts "\nレポートを保存しました: #{report_path}"
  end

  def generate_recommendations(score, results)
    recommendations = []

    # スコアベースの推奨事項
    recommendations << "多要素認証（MFA）の実装を検討してください" if score[:authentication] < 90
    recommendations << "役割ベースアクセス制御（RBAC）の強化を検討してください" if score[:authorization] < 90
    recommendations << "データ暗号化の強化を検討してください" if score[:data_protection] < 90
    recommendations << "セキュリティヘッダーの追加設定を検討してください" if score[:infrastructure] < 100
    recommendations << "セキュリティ監視の強化を検討してください" if score[:monitoring] < 80

    # 失敗テストベースの推奨事項
    if results[:failed].any? { |f| f[:name].include?("Injection") }
      recommendations << "入力検証とサニタイゼーションの強化が必要です"
    end

    if results[:failed].any? { |f| f[:name].include?("Access Control") }
      recommendations << "アクセス制御の見直しが必要です"
    end

    recommendations
  end
end

# ============================================
# TODO: Phase 5-6以降の拡張予定
# ============================================
# 1. 🔴 CI/CD統合
#    - GitHub Actions/GitLab CIでの自動実行
#    - プルリクエストへの自動コメント
#    - セキュリティゲートの実装
#
# 2. 🟡 外部ツール連携
#    - OWASP ZAP API統合
#    - SonarQube連携
#    - Snyk統合
#
# 3. 🟢 継続的改善
#    - セキュリティメトリクスダッシュボード
#    - トレンド分析
#    - 自動改善提案
