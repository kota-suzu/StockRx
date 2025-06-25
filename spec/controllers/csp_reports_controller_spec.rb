# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CspReportsController, type: :controller do
  # CLAUDE.md準拠: CSPレポートコントローラーの包括的テスト
  # メタ認知: セキュリティ監視機能の品質保証と異常系の網羅
  # 横展開: 他のセキュリティ関連コントローラーでも同様のテストパターン適用

  describe "POST #create" do
    let(:valid_csp_report) do
      {
        "csp-report" => {
          "document-uri" => "https://example.com/page",
          "referrer" => "https://example.com/",
          "violated-directive" => "script-src 'self'",
          "effective-directive" => "script-src",
          "original-policy" => "script-src 'self'; object-src 'none'",
          "blocked-uri" => "https://evil.com/malicious.js",
          "status-code" => 200,
          "source-file" => "https://example.com/app.js",
          "line-number" => 10,
          "column-number" => 5
        }
      }
    end

    let(:minimal_csp_report) do
      {
        "csp-report" => {
          "violated-directive" => "script-src 'self'",
          "blocked-uri" => "https://evil.com/malicious.js"
        }
      }
    end

    let(:empty_csp_report) do
      { "csp-report" => {} }
    end

    context "有効なCSPレポート" do
      it "204 No Contentを返す" do
        post :create, params: valid_csp_report, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "レスポンスボディが空である" do
        post :create, params: valid_csp_report, as: :json
        expect(response.body).to be_empty
      end

      it "CSPレポートがログに記録される" do
        expect(Rails.logger).to receive(:warn).with(/CSP Violation/)
        post :create, params: valid_csp_report, as: :json
      end

      it "最小限のフィールドでも処理される" do
        post :create, params: minimal_csp_report, as: :json
        expect(response).to have_http_status(:no_content)
      end
    end

    context "無効なCSPレポート" do
      it "空のcsp-reportでも204を返す" do
        post :create, params: empty_csp_report, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "csp-reportキーがない場合も204を返す" do
        post :create, params: { invalid: "data" }, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "JSONでないデータでも204を返す" do
        post :create, body: "invalid data", as: :text
        expect(response).to have_http_status(:no_content)
      end
    end

    context "セキュリティ考慮事項" do
      it "大量のデータを含むレポートも処理する" do
        large_report = {
          "csp-report" => {
            "violated-directive" => "script-src 'self'",
            "blocked-uri" => "a" * 10000 # 非常に長いURI
          }
        }

        post :create, params: large_report, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "悪意のあるデータを安全に処理する" do
        malicious_report = {
          "csp-report" => {
            "violated-directive" => "<script>alert('XSS')</script>",
            "blocked-uri" => "javascript:alert('XSS')"
          }
        }

        post :create, params: malicious_report, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "ネストが深いJSONも処理する" do
        nested_report = {
          "csp-report" => {
            "custom" => {
              "deep" => {
                "nested" => {
                  "value" => "test"
                }
              }
            }
          }
        }

        post :create, params: nested_report, as: :json
        expect(response).to have_http_status(:no_content)
      end
    end

    context "レート制限" do
      it "短時間での大量リクエストも処理する" do
        10.times do
          post :create, params: valid_csp_report, as: :json
          expect(response).to have_http_status(:no_content)
        end
      end
    end

    context "ロギングとモニタリング" do
      it "違反ディレクティブが記録される" do
        expect(Rails.logger).to receive(:warn).with(/script-src 'self'/)
        post :create, params: valid_csp_report, as: :json
      end

      it "ブロックされたURIが記録される" do
        expect(Rails.logger).to receive(:warn).with(/evil\.com/)
        post :create, params: valid_csp_report, as: :json
      end

      it "ソースファイル情報が記録される" do
        expect(Rails.logger).to receive(:warn).with(/app\.js:10:5/)
        post :create, params: valid_csp_report, as: :json
      end

      it "referrerが記録される" do
        expect(Rails.logger).to receive(:warn).with(/Referrer: https:\/\/example\.com\//)
        post :create, params: valid_csp_report, as: :json
      end
    end

    context "エラーハンドリング" do
      before do
        allow(Rails.logger).to receive(:warn).and_raise(StandardError, "Logging error")
      end

      it "ログエラーが発生しても204を返す" do
        post :create, params: valid_csp_report, as: :json
        expect(response).to have_http_status(:no_content)
      end
    end

    context "パフォーマンス" do
      it "高速にレスポンスを返す" do
        start_time = Time.current
        post :create, params: valid_csp_report, as: :json
        elapsed_time = Time.current - start_time

        expect(elapsed_time).to be < 0.05 # 50ms以内
      end
    end

    context "HTTPメソッド" do
      it "GETリクエストはルーティングエラーになる" do
        expect {
          get :create
        }.to raise_error(ActionController::UrlGenerationError)
      end
    end

    context "Content-Type" do
      it "application/csp-reportを受け入れる" do
        request.headers["Content-Type"] = "application/csp-report"
        post :create, params: valid_csp_report, as: :json
        expect(response).to have_http_status(:no_content)
      end

      it "application/jsonを受け入れる" do
        request.headers["Content-Type"] = "application/json"
        post :create, params: valid_csp_report, as: :json
        expect(response).to have_http_status(:no_content)
      end
    end

    context "将来の拡張" do
      # TODO: Phase 2 - データベース保存機能
      it "CSPレポートのDB保存機能（将来実装）" do
        skip "CSPレポートのデータベース保存は将来実装予定"
      end

      # TODO: Phase 3 - アラート機能
      it "閾値を超えた際のアラート機能（将来実装）" do
        skip "CSP違反アラート機能は将来実装予定"
      end

      # TODO: Phase 4 - 分析ダッシュボード
      it "CSP違反の分析ダッシュボード（将来実装）" do
        skip "CSP違反分析ダッシュボードは将来実装予定"
      end
    end
  end

  describe "ルーティング" do
    it "POSTリクエストが正しくルーティングされる" do
      expect(post: "/csp_reports").to route_to("csp_reports#create")
    end
  end

  describe "セキュリティ設定" do
    it "CSRFトークンの検証がスキップされる" do
      # CSPレポートはブラウザから自動送信されるためCSRF検証不要
      expect(CspReportsController.new.send(:protect_against_forgery?)).to be false
    end
  end
end
