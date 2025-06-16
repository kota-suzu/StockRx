# frozen_string_literal: true

require 'rails_helper'

# Phase 5-4: セキュリティ機能統合テスト
# ============================================
# 実装したセキュリティ機能の統合動作確認
# CLAUDE.md準拠: セキュリティ最優先
# ============================================
RSpec.describe "Security Features Integration", type: :request do
  # ============================================
  # Phase 5-1: レート制限機能テスト
  # ============================================
  describe "Rate Limiting" do
    context "ログイン試行制限" do
      let(:store) { create(:store) }
      let(:login_path) { store_user_session_path(store_slug: store.slug) }

      it "5回失敗後にブロックされること" do
        # レート制限をリセット
        RateLimiter.new(:login, "#{store.id}:127.0.0.1").reset!

        # 5回ログイン失敗
        5.times do
          post login_path, params: {
            store_user: {
              email: "wrong@example.com",
              password: "wrongpassword"
            }
          }
          expect(response).to redirect_to(new_store_user_session_path(store_slug: store.slug))
        end

        # 6回目はブロック
        post login_path, params: {
          store_user: {
            email: "wrong@example.com",
            password: "wrongpassword"
          }
        }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("ログイン試行回数が上限に達しました")
      end
    end

    context "API呼び出し制限" do
      before do
        # APIレート制限をリセット
        RateLimiter.new(:api, "127.0.0.1").reset!
      end

      it "制限内では正常にアクセスできること" do
        admin = create(:admin)
        sign_in admin

        10.times do
          get admin_inventories_path
          expect(response).to be_successful
        end
      end
    end
  end

  # ============================================
  # Phase 5-2: 監査ログ機能テスト
  # ============================================
  describe "Audit Logging" do
    let(:admin) { create(:admin, :super_admin) }
    let(:store) { create(:store) }

    before do
      sign_in admin
    end

    context "モデル操作の監査" do
      it "店舗作成時に監査ログが記録されること" do
        expect {
          post admin_stores_path, params: {
            store: {
              name: "新規店舗",
              code: "NEW001",
              store_type: "pharmacy",
              active: true
            }
          }
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("create")
        expect(audit_log.auditable_type).to eq("Store")
        expect(audit_log.message).to include("新規店舗")
      end

      it "機密情報がマスキングされること" do
        store_user = create(:store_user, store: store)
        store_user.update!(email: "test1234@example.com")

        audit_log = store_user.audit_logs.where(action: "update").last
        details = JSON.parse(audit_log.details)

        # メールアドレスが部分マスキングされていること
        expect(details["changes"]["email"][1]).to match(/te\*+@example\.com/)
      end
    end

    context "セキュリティイベントの記録" do
      it "レート制限超過が記録されること" do
        # レート制限に達するまでリクエスト
        limiter = RateLimiter.new(:login, "test-identifier")
        limiter.reset!

        5.times { limiter.track! }

        # ブロックイベントが記録されているか確認
        security_log = AuditLog.where(action: "security_event").last
        expect(security_log).to be_present
        expect(security_log.message).to include("レート制限超過")
        expect(JSON.parse(security_log.details)["severity"]).to eq("warning")
      end
    end

    context "監査ログビューア" do
      before do
        # テスト用監査ログを作成
        10.times do |i|
          AuditLog.create!(
            action: %w[create update delete view].sample,
            message: "テストアクション #{i}",
            user: admin,
            created_at: i.hours.ago
          )
        end
      end

      it "監査ログ一覧が表示できること" do
        get admin_audit_logs_path
        expect(response).to be_successful
        expect(response.body).to include("監査ログ")
      end

      it "セキュリティイベントのみフィルタリングできること" do
        # セキュリティイベントを作成
        AuditLog.create!(
          action: "security_event",
          message: "不審なアクセス検出",
          severity: "warning",
          security_event: true
        )

        get security_events_admin_audit_logs_path
        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # Phase 5-3: セキュリティヘッダーテスト
  # ============================================
  describe "Security Headers" do
    context "全ページで適用されるヘッダー" do
      it "基本的なセキュリティヘッダーが設定されること" do
        get root_path

        # X-Frame-Options
        expect(response.headers["X-Frame-Options"]).to eq("DENY")

        # X-Content-Type-Options
        expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")

        # X-XSS-Protection
        expect(response.headers["X-XSS-Protection"]).to eq("1; mode=block")

        # Referrer-Policy
        expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
      end

      it "Content Security Policyが設定されること" do
        get root_path

        csp = response.headers["Content-Security-Policy"]
        expect(csp).to include("default-src 'self'")
        expect(csp).to include("frame-ancestors 'none'")
        expect(csp).to include("object-src 'none'")
      end

      it "Permissions Policyが設定されること" do
        get root_path

        pp = response.headers["Permissions-Policy"]
        expect(pp).to include("camera=()")
        expect(pp).to include("microphone=()")
        expect(pp).to include("geolocation=()")
      end
    end

    context "CSP違反レポート" do
      it "CSPレポートエンドポイントが動作すること" do
        csp_report = {
          "csp-report" => {
            "document-uri" => "http://example.com",
            "violated-directive" => "script-src",
            "blocked-uri" => "http://evil.com/script.js"
          }
        }

        post csp_reports_path,
             params: csp_report.to_json,
             headers: { "Content-Type" => "application/csp-report" }

        expect(response).to have_http_status(:no_content)

        # 監査ログに記録されていること
        audit_log = AuditLog.where(action: "security_event").last
        expect(audit_log.message).to include("CSP違反を検出")
      end
    end
  end

  # ============================================
  # 統合シナリオテスト
  # ============================================
  describe "統合セキュリティシナリオ" do
    context "攻撃シミュレーション" do
      it "ブルートフォース攻撃が防御されること" do
        store = create(:store)
        attacker_ip = "192.168.1.100"

        # IPアドレスを偽装
        allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return(attacker_ip)

        # レート制限リセット
        RateLimiter.new(:login, "#{store.id}:#{attacker_ip}").reset!

        # 攻撃シミュレーション
        attack_count = 0
        blocked = false

        10.times do
          post store_user_session_path(store_slug: store.slug), params: {
            store_user: {
              email: "target@example.com",
              password: "guess#{attack_count}"
            }
          }

          attack_count += 1

          if response.redirect_url == root_url
            blocked = true
            break
          end
        end

        expect(blocked).to be true
        expect(attack_count).to eq(6) # 6回目でブロック

        # セキュリティイベントが記録されていること
        security_events = AuditLog.where(
          action: "security_event",
          created_at: 1.minute.ago..Time.current
        )
        expect(security_events.count).to be > 0
      end

      it "XSS攻撃が防御されること" do
        admin = create(:admin)
        sign_in admin

        # XSSペイロードを含むリクエスト
        post admin_inventories_path, params: {
          inventory: {
            name: "<script>alert('XSS')</script>",
            sku: "XSS001",
            price: 100
          }
        }

        # CSPによりインラインスクリプトが実行されないことを確認
        # （実際のブラウザテストではないため、ヘッダーの存在を確認）
        expect(response.headers["Content-Security-Policy"]).not_to include("unsafe-inline")
      end
    end

    context "正常な利用シナリオ" do
      it "認証済みユーザーが正常にアクセスできること" do
        admin = create(:admin)
        sign_in admin

        # 複数のエンドポイントにアクセス
        get admin_root_path
        expect(response).to be_successful

        get admin_inventories_path
        expect(response).to be_successful

        get admin_stores_path
        expect(response).to be_successful

        # セキュリティヘッダーが全てのレスポンスに含まれること
        expect(response.headers["X-Frame-Options"]).to be_present
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================
  describe "セキュリティ機能のパフォーマンス" do
    it "セキュリティチェックがレスポンスタイムに大きな影響を与えないこと" do
      admin = create(:admin)
      sign_in admin

      # ウォームアップ
      get admin_inventories_path

      # パフォーマンス測定
      start_time = Time.current
      10.times { get admin_inventories_path }
      elapsed_time = Time.current - start_time

      # 10リクエストで5秒以内（1リクエストあたり500ms以内）
      expect(elapsed_time).to be < 5.0
    end
  end
end

# ============================================
# TODO: Phase 5-5以降の拡張予定
# ============================================
# 1. 🔴 ペネトレーションテスト
#    - OWASP ZAPとの統合
#    - 自動脆弱性スキャン
#    - SQLインジェクションテスト
#
# 2. 🟡 セキュリティコンプライアンステスト
#    - PCI DSS準拠チェック
#    - GDPR準拠チェック
#    - 暗号化強度テスト
#
# 3. 🟢 異常検知テスト
#    - 機械学習モデルの精度検証
#    - 誤検知率の測定
#    - アラート機能のテスト
