# frozen_string_literal: true

require 'rails_helper'

# Phase 5-5: 自動セキュリティスキャナーテスト
# ============================================
# セキュリティ脆弱性の自動検出
# OWASP ZAP/Burp Suite連携準備
# ============================================
RSpec.describe "Security Scanner", type: :request do
  let(:admin) { create(:admin) }
  let(:store) { create(:store) }
  let(:store_user) { create(:store_user, store: store) }

  # ============================================
  # 脆弱性スキャナー基盤
  # ============================================
  describe "自動脆弱性検出" do
    before do
      sign_in admin
    end

    context "インジェクション脆弱性スキャン" do
      # SQLインジェクションテストペイロード
      SQL_INJECTION_PAYLOADS = [
        "' OR '1'='1",
        "'; DROP TABLE inventories; --",
        "' UNION SELECT * FROM admins --",
        "1' AND SLEEP(5) --",
        "' OR 1=1 --",
        "admin'--",
        "' OR 'x'='x",
        "%27%20OR%20%271%27%3D%271",
        "1' AND (SELECT COUNT(*) FROM admins) > 0 --"
      ].freeze

      it "SQLインジェクションペイロードが無害化されること" do
        SQL_INJECTION_PAYLOADS.each do |payload|
          # 検索パラメータ
          get admin_inventories_path, params: { q: { name_cont: payload } }
          expect(response).to be_successful
          expect(Inventory.table_exists?).to be true

          # フォーム入力
          post admin_inventories_path, params: {
            inventory: {
              name: payload,
              sku: "TEST001",
              price: 100
            }
          }

          # エラーまたはリダイレクト（正常処理）
          expect([ 302, 422 ]).to include(response.status)
        end
      end

      # NoSQLインジェクションテスト
      NOSQL_INJECTION_PAYLOADS = [
        { "$ne" => nil },
        { "$gt" => "" },
        { "$where" => "this.password == 'x'" }
      ].freeze

      it "NoSQLインジェクションペイロードが無害化されること" do
        NOSQL_INJECTION_PAYLOADS.each do |payload|
          get admin_inventories_path, params: { q: payload }
          expect(response.status).to be_between(200, 499)
        end
      end
    end

    context "XSS脆弱性スキャン" do
      # XSSテストペイロード
      XSS_PAYLOADS = [
        "<script>alert('XSS')</script>",
        "<img src=x onerror=alert('XSS')>",
        "<svg onload=alert('XSS')>",
        "javascript:alert('XSS')",
        "<iframe src='javascript:alert(`XSS`)'></iframe>",
        "<input type='text' value='x' onfocus='alert(1)' autofocus>",
        "<script>document.cookie</script>",
        "';alert(String.fromCharCode(88,83,83))//",
        "<IMG SRC=&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;&#97;&#108;&#101;&#114;&#116;&#40;&#39;&#88;&#83;&#83;&#39;&#41;>",
        "<SCRIPT>alert(String.fromCharCode(88,83,83))</SCRIPT>"
      ].freeze

      it "XSSペイロードが適切にエスケープされること" do
        XSS_PAYLOADS.each do |payload|
          post admin_inventories_path, params: {
            inventory: {
              name: payload,
              sku: "XSS001",
              price: 100,
              description: payload
            }
          }

          # 作成されたインベントリを表示
          if response.status == 302
            follow_redirect!

            # スクリプトタグが実行可能な形で含まれていないこと
            expect(response.body).not_to include(payload)
            expect(response.body).to include(CGI.escapeHTML(payload))
          end
        end
      end
    end

    context "パストラバーサル脆弱性スキャン" do
      PATH_TRAVERSAL_PAYLOADS = [
        "../../../etc/passwd",
        "..\\..\\..\\windows\\system32\\config\\sam",
        "....//....//....//etc/passwd",
        "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd",
        "..%252f..%252f..%252fetc%252fpasswd",
        "..%c0%af..%c0%af..%c0%afetc%c0%afpasswd"
      ].freeze

      it "パストラバーサル攻撃が防止されること" do
        PATH_TRAVERSAL_PAYLOADS.each do |payload|
          # ファイルアップロードパラメータ
          file = fixture_file_upload('inventories.csv', 'text/csv')
          allow(file).to receive(:original_filename).and_return(payload)

          post import_admin_inventories_path, params: { file: file }

          # システムファイルにアクセスしていないこと
          expect(response).not_to have_http_status(:success) if payload.include?("etc/passwd")
        end
      end
    end

    context "XXE（XML外部エンティティ）攻撃スキャン" do
      XXE_PAYLOADS = [
        <<~XML,
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
          <data>&xxe;</data>
        XML
        <<~XML
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE foo [<!ENTITY xxe SYSTEM "http://attacker.com/xxe">]>
          <data>&xxe;</data>
        XML
      ].freeze

      it "XXE攻撃が防止されること" do
        XXE_PAYLOADS.each do |payload|
          post admin_inventories_path,
               params: payload,
               headers: { "Content-Type" => "application/xml" }

          # XMLが処理されないか、安全に処理されること
          expect(response).not_to have_http_status(:success)
        end
      end
    end
  end

  # ============================================
  # セキュリティヘッダースキャン
  # ============================================
  describe "セキュリティヘッダーの網羅的チェック" do
    CRITICAL_PATHS = [
      "/",
      "/admin/sign_in",
      "/admin/inventories",
      "/admin/stores",
      "/admin/audit_logs"
    ].freeze

    CRITICAL_PATHS.each do |path|
      context "#{path}のセキュリティヘッダー" do
        before do
          # 管理者ルートには認証が必要
          if path.start_with?('/admin') && path != '/admin/sign_in'
            sign_in admin
          end
          get path
        end

        it "必須セキュリティヘッダーが設定されていること" do
          # OWASP推奨ヘッダー
          expect(response.headers["X-Frame-Options"]).to be_present
          expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
          expect(response.headers["X-XSS-Protection"]).to be_present
          expect(response.headers["Referrer-Policy"]).to be_present
          expect(response.headers["Content-Security-Policy"]).to be_present
          expect(response.headers["Permissions-Policy"]).to be_present
        end

        it "危険なヘッダーが露出していないこと" do
          # 情報漏洩の可能性があるヘッダー
          expect(response.headers["Server"]).to be_nil
          expect(response.headers["X-Powered-By"]).to be_nil
          expect(response.headers["X-AspNet-Version"]).to be_nil
        end
      end
    end
  end

  # ============================================
  # 認証・認可スキャン
  # ============================================
  describe "認証・認可の脆弱性スキャン" do
    context "セッション固定攻撃" do
      it "ログイン前後でセッションIDが変更されること" do
        get new_admin_session_path
        pre_session_id = session.id

        post admin_session_path, params: {
          admin: {
            email: admin.email,
            password: admin.password
          }
        }

        expect(session.id).not_to eq(pre_session_id)
      end
    end

    context "権限昇格攻撃" do
      it "一般ユーザーが管理者機能にアクセスできないこと" do
        # 店舗ユーザーとしてログイン
        post store_user_session_path(store_slug: store.slug), params: {
          store_user: {
            email: store_user.email,
            password: store_user.password
          }
        }

        # 管理者エンドポイントへのアクセス試行
        admin_endpoints = [
          admin_inventories_path,
          admin_stores_path,
          admin_audit_logs_path,
          admin_users_path
        ]

        admin_endpoints.each do |endpoint|
          get endpoint
          expect(response).to redirect_to(new_admin_session_path)
        end
      end
    end

    context "IDOR（Insecure Direct Object Reference）" do
      it "他のリソースに直接アクセスできないこと" do
        other_store = create(:store)
        other_inventory = create(:store_inventory, store: other_store)

        # 自店舗のユーザーとしてログイン
        sign_in store_user

        # 他店舗のリソースへの直接アクセス
        get store_inventory_path(other_inventory, store_slug: store.slug)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ============================================
  # API脆弱性スキャン
  # ============================================
  describe "API脆弱性スキャン" do
    context "マスアサインメント脆弱性" do
      it "保護された属性が更新できないこと" do
        sign_in admin

        # roleやidなどの保護された属性を更新試行
        patch admin_admin_path(admin), params: {
          admin: {
            email: "new@example.com",
            role: "super_admin",
            id: 9999,
            encrypted_password: "hacked"
          }
        }

        admin.reload
        expect(admin.role).not_to eq("super_admin")
        expect(admin.id).not_to eq(9999)
      end
    end

    context "JSONハイジャック" do
      it "JSON配列が直接返されないこと" do
        sign_in admin

        get admin_inventories_path, params: { format: :json }

        if response.content_type.include?("json")
          json = JSON.parse(response.body)
          # ルートが配列でないこと（オブジェクトでラップされていること）
          expect(json).to be_a(Hash) if json.present?
        end
      end
    end
  end

  # ============================================
  # DDoS耐性テスト
  # ============================================
  describe "DDoS攻撃耐性" do
    it "大量リクエストでもシステムが応答すること" do
      sign_in admin

      # 50リクエストを連続送信
      response_times = []
      50.times do
        start_time = Time.current
        get admin_inventories_path
        response_times << (Time.current - start_time)
      end

      # 平均応答時間が1秒以内
      average_time = response_times.sum / response_times.size
      expect(average_time).to be < 1.0

      # 最後のリクエストも成功すること
      expect(response).to be_successful
    end
  end

  # ============================================
  # 暗号化強度テスト
  # ============================================
  describe "暗号化強度チェック" do
    it "パスワードが強力なアルゴリズムで暗号化されること" do
      user = create(:admin, password: "TestPassword123!", password_confirmation: "TestPassword123!")

      # bcryptで暗号化されていること
      expect(user.encrypted_password).to match(/^\$2[ayb]\$/)

      # コストファクターが適切であること（10以上推奨）
      cost = user.encrypted_password.match(/\$2[ayb]\$(\d+)\$/)[1].to_i
      expect(cost).to be >= 10
    end

    it "セッションクッキーが安全に設定されること" do
      post admin_session_path, params: {
        admin: {
          email: admin.email,
          password: admin.password
        }
      }

      # Secureフラグの確認（本番環境でのみ）
      if Rails.env.production?
        expect(response.headers["Set-Cookie"]).to include("secure")
      end

      # HttpOnlyフラグの確認 (Rails uses lowercase)
      expect(response.headers["Set-Cookie"]).to include("httponly")
    end
  end
end

# ============================================
# TODO: Phase 5-6以降の拡張予定
# ============================================
# 1. 🔴 外部スキャナー統合
#    - OWASP ZAP APIクライアント実装
#    - Burp Suite連携
#    - 自動スキャン結果のレポート生成
#
# 2. 🟡 継続的セキュリティテスト
#    - CI/CDパイプラインへの統合
#    - 定期的な脆弱性スキャン
#    - セキュリティレグレッションテスト
#
# 3. 🟢 脅威モデリング
#    - STRIDE分析の自動化
#    - 攻撃ツリーの生成
#    - リスクスコアリング
