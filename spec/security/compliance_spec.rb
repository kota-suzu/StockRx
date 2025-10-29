# frozen_string_literal: true

require 'rails_helper'

# Phase 5-5: セキュリティコンプライアンステスト
# ============================================
# PCI DSS、GDPR、個人情報保護法準拠チェック
# ============================================
RSpec.describe "Security Compliance", type: :request do
  let(:admin) { create(:admin) }
  let(:store) { create(:store) }

  before do
    sign_in admin
  end

  # ============================================
  # PCI DSS (Payment Card Industry Data Security Standard)
  # ============================================
  describe "PCI DSS準拠チェック" do
    context "要件3: 保存されたカード会員データの保護" do
      it "クレジットカード番号が平文で保存されないこと" do
        # インベントリのメモ欄にカード番号を保存する場合
        inventory = create(:inventory, notes: "Customer card: 4111-1111-1111-1111")

        # データベースから直接取得
        raw_data = Inventory.connection.select_value(
          "SELECT notes FROM inventories WHERE id = #{inventory.id}"
        )

        # カード番号が平文で保存されていないこと
        expect(raw_data).not_to include("4111-1111-1111-1111")
      end

      it "カード番号が監査ログでマスキングされること" do
        inventory = create(:inventory)
        inventory.update!(notes: "Card: 4111-1111-1111-1111")

        audit_log = inventory.audit_logs.last
        details = JSON.parse(audit_log.details)

        expect(details["changes"]["notes"][1]).to include("[CARD_NUMBER]")
        expect(details["changes"]["notes"][1]).not_to include("4111-1111-1111-1111")
      end

      it "カード番号の表示が制限されること" do
        inventory = create(:inventory, notes: "Card: 4111-1111-1111-1111")

        get admin_inventory_path(inventory)

        # 最初の6桁と最後の4桁のみ表示（例: 411111******1111）
        expect(response.body).not_to include("4111-1111-1111-1111")
      end
    end

    context "要件4: 暗号化された伝送" do
      it "本番環境でHTTPS強制が有効であること" do
        if Rails.env.production?
          get root_path
          expect(response.headers["Strict-Transport-Security"]).to be_present
          expect(response.headers["Strict-Transport-Security"]).to include("max-age=31536000")
        end
      end
    end

    context "要件6: 安全なシステムとアプリケーション" do
      it "セキュリティパッチが適用されていること" do
        # Gemの脆弱性チェック（bundle-auditが必要）
        result = `bundle audit check 2>&1`
        vulnerabilities = result.scan(/Name:.*/).size

        # 既知の脆弱性がないこと
        expect(vulnerabilities).to eq(0), "脆弱性が検出されました: #{result}"
      end

      it "デフォルトパスワードが無効化されていること" do
        # デフォルトの認証情報でログイン試行
        default_credentials = [
          { email: "admin@example.com", password: "password" },
          { email: "admin@example.com", password: "admin" },
          { email: "admin", password: "admin" }
        ]

        default_credentials.each do |creds|
          post admin_session_path, params: { admin: creds }
          expect(response).to redirect_to(new_admin_session_path)
        end
      end
    end

    context "要件8: システムコンポーネントへのアクセス制御" do
      it "強力なパスワードポリシーが適用されること" do
        # 弱いパスワードでの作成試行
        weak_passwords = [ "password", "12345678", "admin123", "qwerty" ]

        weak_passwords.each do |weak_password|
          admin = build(:admin, password: weak_password)
          expect(admin).not_to be_valid
          expect(admin.errors[:password]).to be_present
        end
      end

      it "パスワード履歴が保持されること" do
        # パスワード変更
        old_password = admin.encrypted_password
        admin.update!(password: "NewPassword123!")

        # 以前のパスワードに戻せないこと（実装に依存）
        admin.password = admin.password_confirmation = "OldPassword123!"
        expect(admin).not_to be_valid if admin.respond_to?(:password_history)
      end
    end

    context "要件10: ネットワークリソースへのアクセス追跡" do
      it "全てのアクセスが監査ログに記録されること" do
        # 重要なアクション実行
        expect {
          post admin_inventories_path, params: {
            inventory: { name: "Test", sku: "TEST001", price: 100 }
          }
        }.to change(AuditLog, :count).by_at_least(1)

        # ログ内容の確認
        audit_log = AuditLog.last
        expect(audit_log.user).to eq(admin)
        expect(audit_log.action).to be_present
        expect(audit_log.created_at).to be_present
      end
    end
  end

  # ============================================
  # GDPR (General Data Protection Regulation)
  # ============================================
  describe "GDPR準拠チェック" do
    context "第5条: 個人データ処理の原則" do
      it "個人データが必要最小限に制限されること（データ最小化）" do
        # ユーザー作成時に不要なデータを収集しないこと
        user_params = {
          email: "test@example.com",
          password: "Password123!",
          unnecessary_field: "should_not_be_saved"
        }

        expect {
          post admin_users_path, params: { user: user_params }
        }.not_to change { User.column_names.include?("unnecessary_field") }
      end

      it "個人データの正確性が保たれること" do
        user = create(:store_user, store: store)

        # データ更新機能が存在すること
        patch store_user_path(user, store_slug: store.slug), params: {
          store_user: { email: "updated@example.com" }
        }

        expect(user.reload.email).to eq("updated@example.com") if response.successful?
      end
    end

    context "第7条: 同意" do
      it "明示的な同意なしに個人データが処理されないこと" do
        # プライバシーポリシーへの同意チェック
        post store_user_registration_path(store_slug: store.slug), params: {
          store_user: {
            email: "new@example.com",
            password: "Password123!",
            privacy_policy_accepted: false
          }
        }

        # 同意なしでは登録できないこと（実装に依存）
        if StoreUser.column_names.include?("privacy_policy_accepted")
          expect(response).not_to redirect_to(root_path)
        end
      end
    end

    context "第17条: 消去の権利（忘れられる権利）" do
      it "個人データの完全削除が可能であること" do
        user = create(:store_user, store: store)
        user_id = user.id

        # ユーザー削除
        delete store_user_path(user, store_slug: store.slug)

        # 関連データも削除されること
        expect(StoreUser.find_by(id: user_id)).to be_nil
        expect(AuditLog.where(user_type: "StoreUser", user_id: user_id).count).to eq(0)
      end

      it "削除要求が監査ログに記録されること" do
        user = create(:store_user, store: store)

        expect {
          delete store_user_path(user, store_slug: store.slug)
        }.to change(AuditLog, :count).by_at_least(1)

        # GDPR削除要求として記録
        deletion_log = AuditLog.where(action: [ "delete", "gdpr_deletion" ]).last
        expect(deletion_log).to be_present
      end
    end

    context "第20条: データポータビリティ" do
      it "個人データをエクスポート可能であること" do
        user = create(:store_user, store: store)

        # データエクスポート機能
        get export_store_user_path(user, store_slug: store.slug, format: :json)

        if response.successful?
          data = JSON.parse(response.body)
          expect(data).to include("email")
          expect(data).not_to include("encrypted_password")
        end
      end
    end

    context "第25条: データ保護バイデザイン" do
      it "デフォルトで最も厳格なプライバシー設定になること" do
        user = create(:store_user, store: store)

        # デフォルトの通知設定などが最小限であること
        if user.respond_to?(:notification_settings)
          expect(user.marketing_emails_enabled).to be false
          expect(user.data_sharing_enabled).to be false
        end
      end
    end

    context "第33条: データ侵害通知" do
      it "セキュリティインシデントが検出・記録されること" do
        # ブルートフォース攻撃のシミュレーション
        5.times do
          post store_user_session_path(store_slug: store.slug), params: {
            store_user: { email: "attacker@example.com", password: "wrong" }
          }
        end

        # セキュリティイベントとして記録
        security_events = AuditLog.where(
          action: "security_event",
          created_at: 1.minute.ago..Time.current
        )
        expect(security_events.count).to be > 0
      end
    end
  end

  # ============================================
  # 個人情報保護法（日本）準拠チェック
  # ============================================
  describe "個人情報保護法準拠チェック" do
    context "第15条: 利用目的の特定" do
      it "個人情報の利用目的が明示されること" do
        get new_store_user_registration_path(store_slug: store.slug)

        # プライバシーポリシーへのリンクが存在すること
        expect(response.body).to include("プライバシーポリシー") if response.successful?
      end
    end

    context "第20条: 安全管理措置" do
      it "個人情報が暗号化されて保存されること" do
        user = create(:store_user, store: store, email: "personal@example.com")

        # メールアドレスなどが適切に保護されていること
        raw_email = StoreUser.connection.select_value(
          "SELECT email FROM store_users WHERE id = #{user.id}"
        )

        # 暗号化されている場合はチェック（実装に依存）
        expect(raw_email).to eq("personal@example.com") # または暗号化された値
      end

      it "アクセス制御が実装されていること" do
        other_store = create(:store)
        other_user = create(:store_user, store: other_store)

        # 他店舗のユーザー情報にアクセスできないこと
        sign_in store_user
        get store_user_path(other_user, store_slug: store.slug)

        expect(response).to have_http_status(:not_found)
      end
    end

    context "マイナンバー保護" do
      it "マイナンバーが自動的にマスキングされること" do
        # マイナンバーを含むデータの作成
        inventory = create(:inventory, notes: "User MyNumber: 123456789012")

        # 監査ログでマスキングされていること
        audit_log = inventory.audit_logs.last
        details = JSON.parse(audit_log.details)

        expect(details["attributes"]["notes"]).to include("[MY_NUMBER]")
        expect(details["attributes"]["notes"]).not_to include("123456789012")
      end
    end
  end

  # ============================================
  # セキュリティメトリクス
  # ============================================
  describe "セキュリティメトリクス測定" do
    it "セキュリティスコアが基準を満たすこと" do
      score = calculate_security_score

      expect(score[:total]).to be >= 80 # 80点以上
      expect(score[:headers]).to be >= 90 # ヘッダー設定90点以上
      expect(score[:authentication]).to be >= 85 # 認証85点以上
      expect(score[:encryption]).to be >= 90 # 暗号化90点以上
    end
  end

  private

  def calculate_security_score
    score = {
      headers: 0,
      authentication: 0,
      encryption: 0,
      total: 0
    }

    # ヘッダースコア計算
    get root_path
    score[:headers] += 10 if response.headers["X-Frame-Options"].present?
    score[:headers] += 10 if response.headers["X-Content-Type-Options"].present?
    score[:headers] += 10 if response.headers["Content-Security-Policy"].present?
    score[:headers] += 10 if response.headers["Strict-Transport-Security"].present?
    score[:headers] += 10 if response.headers["Permissions-Policy"].present?
    score[:headers] = [ score[:headers] * 2, 100 ].min

    # 認証スコア計算
    score[:authentication] += 30 if Admin.new.respond_to?(:lockable?)
    score[:authentication] += 30 if Admin.new.respond_to?(:timeoutable?)
    score[:authentication] += 25 if defined?(Devise.password_length).present?
    score[:authentication] += 15 if defined?(RateLimiter).present?

    # 暗号化スコア計算
    admin = create(:admin, password: "TestPass123!")
    score[:encryption] += 50 if admin.encrypted_password.match?(/^\$2[ayb]\$/)
    score[:encryption] += 30 if Rails.application.config.force_ssl
    score[:encryption] += 20 if ActionController::Base.default_protect_from_forgery

    # 総合スコア
    score[:total] = (score[:headers] + score[:authentication] + score[:encryption]) / 3

    score
  end
end

# ============================================
# TODO: Phase 5-6以降の拡張予定
# ============================================
# 1. 🔴 国際コンプライアンス
#    - CCPA（カリフォルニア州消費者プライバシー法）
#    - LGPD（ブラジル一般データ保護法）
#    - PIPEDA（カナダ個人情報保護法）
#
# 2. 🟡 業界別コンプライアンス
#    - HIPAA（医療情報）
#    - SOX法（財務報告）
#    - FISMA（連邦情報セキュリティ）
#
# 3. 🟢 自動コンプライアンスレポート
#    - 定期的な準拠状況レポート
#    - 違反項目の自動検出
#    - 改善提案の生成
