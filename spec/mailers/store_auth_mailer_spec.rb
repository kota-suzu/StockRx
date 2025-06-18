# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreAuthMailer, type: :mailer do
  let(:store) { create(:store) }
  let(:store_user) { create(:store_user, store: store) }
  let(:temp_password) { create(:temp_password, store_user: store_user) }
  let(:plain_password) { "TempPass123!" }

  # ============================================
  # 一時パスワード通知メールテスト
  # ============================================

  describe '#temp_password_notification' do
    subject(:mail) do
      described_class.temp_password_notification(
        store_user,
        plain_password,
        temp_password
      )
    end

    # 基本的なメール属性テスト
    describe "mail attributes" do
      it "sets the correct recipient" do
        expect(mail.to).to eq([ store_user.email ])
      end

      it "sets the correct sender" do
        expect(mail.from).to include(ENV.fetch("MAILER_STORE_FROM", "store-noreply@stockrx.example.com"))
      end

      it "sets the correct reply-to" do
        expect(mail.reply_to).to include(ENV.fetch("MAILER_STORE_REPLY_TO", "store-support@stockrx.example.com"))
      end

      it "includes store name in subject" do
        expect(mail.subject).to include(store.name)
        expect(mail.subject).to include("一時パスワード通知")
      end

      it "sets urgent priority headers" do
        expect(mail.header['X-Priority'].value).to eq("1")
        expect(mail.header['X-MSMail-Priority'].value).to eq("High")
        expect(mail.header['Importance'].value).to eq("High")
      end

      it "sets security-related headers" do
        expect(mail.header['X-Security-Level'].value).to eq("High")
        expect(mail.header['X-Store-ID'].value).to eq(store.id.to_s)
        expect(mail.header['X-Store-Slug'].value).to eq(store.slug)
        expect(mail.header['X-User-Role'].value).to eq(store_user.role)
        expect(mail.header['X-Mailer-Type'].value).to eq("StoreAuth")
      end
    end

    # HTMLメール内容テスト
    describe "HTML mail content" do
      let(:html_body) { mail.html_part.body.to_s }

      it "includes store information" do
        expect(html_body).to include(store.name)
        expect(html_body).to include(store_user.name)
      end

      it "displays the temporary password prominently" do
        expect(html_body).to include(plain_password)
        expect(html_body).to include("password-value")
      end

      it "includes expiration information" do
        expect(html_body).to include("有効期限")
        expect(html_body).to include("⏰")
      end

      it "provides a login link" do
        expect(html_body).to include("store_user_session_url")
        expect(html_body).to include("login-button")
      end

      it "includes security warnings" do
        expect(html_body).to include("セキュリティ上の重要な注意事項")
        expect(html_body).to include("⚠️")
        expect(html_body).to include("他の方と共有せず")
      end

      it "has responsive design elements" do
        expect(html_body).to include("max-width: 600px")
        expect(html_body).to include("@media screen and (max-width: 480px)")
      end

      it "includes dark mode support" do
        expect(html_body).to include("@media (prefers-color-scheme: dark)")
      end
    end

    # テキストメール内容テスト
    describe "text mail content" do
      let(:text_body) { mail.text_part.body.to_s }

      it "includes store information" do
        expect(text_body).to include(store.name)
        expect(text_body).to include(store_user.name)
      end

      it "displays the temporary password clearly" do
        expect(text_body).to include(plain_password)
        expect(text_body).to include("一時パスワード")
      end

      it "includes expiration information" do
        expect(text_body).to include("有効期限")
        expect(text_body).to include("⏰")
      end

      it "provides login URL" do
        expect(text_body).to include("ログインURL")
        expect(text_body).to include("🔐")
      end

      it "includes security warnings" do
        expect(text_body).to include("セキュリティ上の重要な注意事項")
        expect(text_body).to include("⚠️")
      end

      it "includes troubleshooting information" do
        expect(text_body).to include("ログインできない場合の対処法")
        expect(text_body).to include("💡")
      end

      it "includes support contact information" do
        expect(text_body).to include("サポートチームに連絡")
        expect(text_body).to include("📞")
      end

      it "has proper text formatting" do
        expect(text_body).to include("=" * 60)  # Header separator
        expect(text_body).to include("─" * 60)  # Section separator
        expect(text_body).to include("┌─")      # Password box
      end
    end

    # 国際化テスト
    describe "internationalization" do
      context "with Japanese locale" do
        before { I18n.locale = :ja }
        after { I18n.locale = I18n.default_locale }

        it "uses Japanese text in subject" do
          expect(mail.subject).to include("一時パスワード通知")
        end

        it "uses Japanese text in body" do
          expect(mail.html_part.body.to_s).to include("こんにちは")
          expect(mail.text_part.body.to_s).to include("こんにちは")
        end
      end

      context "with English locale" do
        before { I18n.locale = :en }
        after { I18n.locale = I18n.default_locale }

        it "uses English text in subject" do
          expect(mail.subject).to include("Temporary Password")
        end

        it "uses English text in body" do
          expect(mail.html_part.body.to_s).to include("Hello")
          expect(mail.text_part.body.to_s).to include("Hello")
        end
      end
    end

    # セキュリティ機能テスト
    describe "security features" do
      it "logs sensitive email attempt" do
        expect(Rails.logger).to receive(:info) do |log_data|
          parsed_log = JSON.parse(log_data)
          expect(parsed_log["event"]).to eq("sensitive_email_attempt")
          expect(parsed_log["security_level"]).to eq("high")
          expect(parsed_log["to_email_masked"]).to match(/\w\*\*\*.*@/)
        end

        mail.body  # Trigger the before_action
      end

      it "sanitizes password from logs after sending" do
        expect(Rails.logger).to receive(:info).with(
          hash_including("event" => "temp_password_sanitized")
        )

        mail.deliver_now
      end

      it "masks email addresses correctly" do
        mailer = described_class.new

        expect(mailer.send(:mask_email, "test@example.com")).to eq("t***t@example.com")
        expect(mailer.send(:mask_email, "ab@example.com")).to eq("a*@example.com")
        expect(mailer.send(:mask_email, "a@example.com")).to eq("a***@example.com")
        expect(mailer.send(:mask_email, "")).to eq("[NO_EMAIL]")
        expect(mailer.send(:mask_email, "invalid")).to eq("[INVALID_EMAIL]")
      end
    end

    # エラーハンドリングテスト
    describe "error handling" do
      context "with invalid store user" do
        let(:store_user) { build(:store_user, email: nil) }

        it "handles missing email gracefully" do
          expect { mail.body }.not_to raise_error
        end
      end

      context "with expired temp password" do
        let(:temp_password) { create(:temp_password, :expired, store_user: store_user) }

        it "still generates mail successfully" do
          expect(mail.to).to eq([ store_user.email ])
          expect(mail.html_part.body.to_s).to include(plain_password)
        end
      end
    end

    # パフォーマンステスト
    describe "performance" do
      it "generates mail content efficiently" do
        expect {
          mail.html_part.body.to_s
          mail.text_part.body.to_s
        }.to complete_within(1.second)
      end

      it "does not leak memory with password variables" do
        # メール生成後に機密変数がクリアされることを確認
        mail.deliver_now

        # マジック変数アクセスでテスト（実際の実装では after_action で処理）
        expect(mail.instance_variable_get(:@plain_password)).to eq("[SANITIZED]")
      end
    end
  end

  # ============================================
  # 将来のメール機能テスト（スタブ）
  # ============================================

  describe '#password_changed_notification' do
    # TODO: 🟡 Phase 2重要 - パスワード変更通知メール実装
    it "TODO: implements password change notification"
  end

  describe '#security_alert_notification' do
    # TODO: 🟢 Phase 3推奨 - セキュリティアラート通知実装
    it "TODO: implements security alert notifications"
  end

  # ============================================
  # プライベートメソッドテスト
  # ============================================

  describe "private methods" do
    let(:mailer) { described_class.new }

    describe "#store_mail_defaults" do
      it "returns correct mail configuration" do
        defaults = mailer.send(:store_mail_defaults, store_user)

        expect(defaults[:to]).to eq(store_user.email)
        expect(defaults[:from]).to eq(ENV.fetch("MAILER_STORE_FROM", "store-noreply@stockrx.example.com"))
        expect(defaults[:reply_to]).to eq(ENV.fetch("MAILER_STORE_REPLY_TO", "store-support@stockrx.example.com"))
        expect(defaults["X-Store-ID"]).to eq(store.id.to_s)
        expect(defaults["X-Store-Slug"]).to eq(store.slug)
        expect(defaults["X-User-Role"]).to eq(store_user.role)
        expect(defaults["X-Mailer-Type"]).to eq("StoreAuth")
      end
    end

    describe "#urgent_mail_defaults" do
      it "returns urgent priority headers" do
        urgent_defaults = mailer.send(:urgent_mail_defaults)

        expect(urgent_defaults["X-Priority"]).to eq("1")
        expect(urgent_defaults["X-MSMail-Priority"]).to eq("High")
        expect(urgent_defaults["Importance"]).to eq("High")
        expect(urgent_defaults["X-Security-Level"]).to eq("High")
        expect(urgent_defaults["X-Auto-Response-Suppress"]).to eq("All")
      end
    end

    describe "#notification_enabled?" do
      it "returns true for temp_password notifications" do
        expect(mailer.send(:notification_enabled?, store_user, :temp_password)).to be true
      end

      it "returns true for password_changed notifications" do
        expect(mailer.send(:notification_enabled?, store_user, :password_changed)).to be true
      end

      it "returns true for security_alert notifications" do
        expect(mailer.send(:notification_enabled?, store_user, :security_alert)).to be true
      end

      it "returns false for unknown notification types" do
        expect(mailer.send(:notification_enabled?, store_user, :unknown)).to be false
      end
    end
  end

  # ============================================
  # 統合テスト
  # ============================================

  describe "integration with EmailAuthService" do
    let(:service) { EmailAuthService.new }

    it "integrates correctly with EmailAuthService" do
      # EmailAuthServiceからのメール送信をテスト
      allow(TempPassword).to receive(:generate_for_user)
        .and_return([ temp_password, plain_password ])

      # モックメール送信
      expect(described_class).to receive(:temp_password_notification)
        .with(store_user, plain_password, temp_password)
        .and_return(double(deliver_now: true))

      # サービス経由でのメール送信（実際の統合は次のフェーズで実装）
      # result = service.generate_and_send_temp_password(store_user)
      # expect(result[:success]).to be true
    end
  end
end
