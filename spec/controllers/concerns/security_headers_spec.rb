# frozen_string_literal: true

require 'rails_helper'

# Phase 5-4: SecurityHeadersConcernテスト
# ============================================
# セキュリティヘッダー設定機能のテスト
# ============================================
RSpec.describe SecurityHeaders, type: :controller do
  # テスト用コントローラー
  controller(ApplicationController) do
    def index
      render plain: "OK"
    end

    def with_script
      # nonceを使用したスクリプト例
      @script_content = "console.log('Hello');"
      render inline: <<~HTML
        <html>
          <body>
            <script nonce="<%= content_security_policy_nonce %>">
              <%= @script_content %>
            </script>
          </body>
        </html>
      HTML
    end
  end

  before do
    routes.draw do
      get "index" => "anonymous#index"
      get "with_script" => "anonymous#with_script"
    end
  end

  describe "基本的なセキュリティヘッダー" do
    before { get :index }

    it "X-Frame-Optionsが設定されること" do
      expect(response.headers["X-Frame-Options"]).to eq("DENY")
    end

    it "X-Content-Type-Optionsが設定されること" do
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end

    it "X-XSS-Protectionが設定されること" do
      expect(response.headers["X-XSS-Protection"]).to eq("1; mode=block")
    end

    it "Referrer-Policyが設定されること" do
      expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
    end

    it "カスタムヘッダーが設定されること" do
      expect(response.headers["X-Application-Name"]).to eq("StockRx")
      expect(response.headers["X-Security-Version"]).to eq("5.3")
    end
  end

  describe "Content Security Policy" do
    before { get :index }

    it "CSPヘッダーが設定されること" do
      expect(response.headers["Content-Security-Policy"]).to be_present
    end

    it "基本的なCSPディレクティブが含まれること" do
      csp = response.headers["Content-Security-Policy"]

      expect(csp).to include("default-src 'self'")
      expect(csp).to include("frame-src 'none'")
      expect(csp).to include("object-src 'none'")
      expect(csp).to include("base-uri 'self'")
      expect(csp).to include("frame-ancestors 'none'")
    end

    it "開発環境では緩和された設定になること" do
      allow(Rails.env).to receive(:development?).and_return(true)
      get :index

      csp = response.headers["Content-Security-Policy"]
      expect(csp).to include("script-src 'self' 'unsafe-inline' 'unsafe-eval'")
    end

    it "本番環境ではnonceベースの設定になること" do
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:production?).and_return(true)
      get :index

      csp = response.headers["Content-Security-Policy"]
      expect(csp).to match(/script-src 'self' 'nonce-[\w+\/=]+'/)
      expect(csp).not_to include("unsafe-inline")
    end

    it "CSPレポートURIが設定されること" do
      allow_any_instance_of(controller.class).to receive(:csp_report_uri).and_return("/csp-reports")
      get :index

      csp = response.headers["Content-Security-Policy"]
      expect(csp).to include("report-uri /csp-reports")
      expect(csp).to include("report-to csp-endpoint")
    end
  end

  describe "Permissions Policy" do
    before { get :index }

    it "Permissions Policyヘッダーが設定されること" do
      expect(response.headers["Permissions-Policy"]).to be_present
    end

    it "各種権限が適切に設定されること" do
      pp = response.headers["Permissions-Policy"]

      # 危険な機能は無効化
      expect(pp).to include("camera=()")
      expect(pp).to include("microphone=()")
      expect(pp).to include("geolocation=()")
      expect(pp).to include("payment=()")
      expect(pp).to include("usb=()")

      # 一部機能は自サイトのみ許可
      expect(pp).to include("fullscreen=(self)")
    end
  end

  describe "HTTPS関連ヘッダー" do
    context "本番環境" do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        get :index
      end

      it "Strict-Transport-Securityが設定されること" do
        expect(response.headers["Strict-Transport-Security"]).to eq(
          "max-age=31536000; includeSubDomains; preload"
        )
      end
    end

    context "開発環境" do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(Rails.env).to receive(:production?).and_return(false)
        get :index
      end

      it "Strict-Transport-Securityが設定されないこと" do
        expect(response.headers["Strict-Transport-Security"]).to be_nil
      end
    end
  end

  describe "CSP nonce機能" do
    it "nonceが生成されること" do
      get :index
      expect(controller.send(:content_security_policy_nonce)).to match(/[\w+\/=]+/)
    end

    it "同一リクエスト内で同じnonceが返されること" do
      get :index
      nonce1 = controller.send(:content_security_policy_nonce)
      nonce2 = controller.send(:content_security_policy_nonce)
      expect(nonce1).to eq(nonce2)
    end

    it "異なるリクエストで異なるnonceが生成されること" do
      get :index
      nonce1 = controller.send(:content_security_policy_nonce)

      get :index
      nonce2 = controller.send(:content_security_policy_nonce)

      expect(nonce1).not_to eq(nonce2)
    end

    it "ビューでnonceが使用できること" do
      get :with_script

      # レスポンスにnonceが含まれていること
      expect(response.body).to match(/<script nonce="[\w+\/=]+">/)

      # CSPヘッダーのnonceと一致すること
      nonce = controller.send(:content_security_policy_nonce)
      expect(response.body).to include(%Q(nonce="#{nonce}"))
    end
  end

  describe "ヘルパーメソッド" do
    it "nonce_javascript_tagが使用できること" do
      # ヘルパーメソッドのテスト
      helper = Object.new
      helper.extend(SecurityHeaders)
      helper.extend(ActionView::Helpers::TagHelper)
      helper.extend(ActionView::Helpers::CaptureHelper)

      allow(helper).to receive(:content_security_policy_nonce).and_return("test-nonce")

      tag = helper.nonce_javascript_tag { "alert('test');" }
      expect(tag).to eq('<script nonce="test-nonce">alert(\'test\');</script>')
    end
  end

  describe "WebSocket URL設定" do
    it "開発環境でWebSocket URLが含まれること" do
      allow(Rails.env).to receive(:development?).and_return(true)
      get :index

      csp = response.headers["Content-Security-Policy"]
      expect(csp).to include("ws://localhost:*")
      expect(csp).to include("wss://localhost:*")
    end
  end

  describe "エラーハンドリング" do
    it "CSPレポートURI生成エラーが処理されること" do
      allow(Rails.application.routes.url_helpers).to receive(:csp_reports_path).and_raise(StandardError)
      allow(Rails.logger).to receive(:error)

      get :index

      # エラーが発生してもレスポンスは正常
      expect(response).to be_successful
      expect(Rails.logger).to have_received(:error).with(/CSP report URI generation failed/)
    end
  end
end

# ============================================
# TODO: Phase 5-5以降の拡張予定
# ============================================
# 1. 🔴 CSP違反のシミュレーション
#    - 実際のXSS攻撃パターン
#    - インラインスクリプトのブロック確認
#
# 2. 🟡 ブラウザ互換性テスト
#    - 各ブラウザでのヘッダー解釈
#    - レガシーブラウザ対応
#
# 3. 🟢 パフォーマンステスト
#    - ヘッダー生成のオーバーヘッド
#    - nonce生成の負荷測定
