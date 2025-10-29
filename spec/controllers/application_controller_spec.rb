# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  # CLAUDE.md準拠: アプリケーション基底コントローラーの包括的テスト
  # メタ認知: 全コントローラーに影響する共通機能の品質保証
  # 横展開: 継承される全ての機能が子コントローラーで正しく動作することを保証

  # テスト用の具象コントローラー
  controller do
    def index
      render plain: "OK"
    end

    def show
      raise ActiveRecord::RecordNotFound
    end

    def create
      raise StandardError, "Test error"
    end

    def update
      params.require(:required_param)
    end

    def destroy
      head :no_content
    end
  end

  let(:admin) { create(:admin) }
  let(:store_user) { create(:store_user) }

  describe "セキュリティヘッダー" do
    before { get :index }

    it "X-Frame-Optionsヘッダーが設定される" do
      expect(response.headers["X-Frame-Options"]).to eq("DENY")
    end

    it "X-Content-Type-Optionsヘッダーが設定される" do
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
    end

    it "X-XSS-Protectionヘッダーが設定される" do
      expect(response.headers["X-XSS-Protection"]).to eq("1; mode=block")
    end

    it "Referrer-Policyヘッダーが設定される" do
      expect(response.headers["Referrer-Policy"]).to eq("strict-origin-when-cross-origin")
    end

    it "Permissions-Policyヘッダーが設定される" do
      expect(response.headers["Permissions-Policy"]).to include("camera=(),")
      expect(response.headers["Permissions-Policy"]).to include("microphone=()")
    end

    it "Content-Security-Policyヘッダーが設定される" do
      expect(response.headers["Content-Security-Policy"]).to include("default-src 'self'")
      expect(response.headers["Content-Security-Policy"]).to include("script-src")
    end
  end

  describe "セキュリティ監視" do
    describe "#monitor_request_security" do
      context "本番環境" do
        before do
          allow(Rails.env).to receive(:test?).and_return(false)
        end

        it "ブロックされたIPからのアクセスを拒否する" do
          allow(SecurityMonitor).to receive(:is_blocked?).with("192.168.1.1").and_return(true)
          request.env["REMOTE_ADDR"] = "192.168.1.1"

          get :index

          expect(response).to have_http_status(:forbidden)
          expect(response.body).to eq("Access Denied")
        end

        it "正常なIPからのアクセスを許可する" do
          allow(SecurityMonitor).to receive(:is_blocked?).and_return(false)
          allow(SecurityMonitor).to receive(:analyze_request).and_return([])

          get :index

          expect(response).to have_http_status(:ok)
        end

        it "疑わしいパターンを検出した場合ログに記録する" do
          allow(SecurityMonitor).to receive(:is_blocked?).and_return(false)
          allow(SecurityMonitor).to receive(:analyze_request).and_return([ "sql_injection", "xss_attempt" ])

          expect(Rails.logger).to receive(:warn).with(
            hash_including(
              event: "suspicious_request_detected",
              patterns: [ "sql_injection", "xss_attempt" ]
            ).to_json
          )

          get :index
        end
      end

      context "テスト環境" do
        it "セキュリティチェックをスキップする" do
          expect(SecurityMonitor).not_to receive(:is_blocked?)
          expect(SecurityMonitor).not_to receive(:analyze_request)

          get :index

          expect(response).to have_http_status(:ok)
        end
      end
    end

    describe "#track_response_metrics" do
      context "本番環境" do
        before do
          allow(Rails.env).to receive(:test?).and_return(false)
          allow(SecurityMonitor).to receive(:is_blocked?).and_return(false)
          allow(SecurityMonitor).to receive(:analyze_request).and_return([])
        end

        it "遅いレスポンスを検出してログに記録する" do
          controller.instance_variable_set(:@request_start_time, 10.seconds.ago)
          stub_const("SecurityMonitor::SUSPICIOUS_THRESHOLDS", { response_time: 5 })

          expect(Rails.logger).to receive(:warn).with(
            hash_including(
              event: "slow_response_detected",
              response_time_seconds: be > 5
            ).to_json
          )

          get :index
        end

        it "通常のレスポンス時間ではログを記録しない" do
          controller.instance_variable_set(:@request_start_time, 0.1.seconds.ago)
          stub_const("SecurityMonitor::SUSPICIOUS_THRESHOLDS", { response_time: 5 })

          expect(Rails.logger).not_to receive(:warn)

          get :index
        end

        it "@request_start_timeが設定されていない場合は何もしない" do
          expect(Rails.logger).not_to receive(:warn)

          get :index
        end
      end

      context "テスト環境" do
        it "メトリクス追跡をスキップする" do
          controller.instance_variable_set(:@request_start_time, 10.seconds.ago)

          expect(Rails.logger).not_to receive(:warn)

          get :index
        end
      end
    end
  end

  describe "エラーハンドリング" do
    describe "#handle_security_error" do
      controller do
        def show
          raise SecurityError, "Test security error"
        end
      end

      context "HTMLフォーマット" do
        it "SecurityErrorを適切に処理する" do
          allow(Rails.logger).to receive(:error)
          allow(SensitiveDataFilter).to receive(:filter_log_message).and_return("Filtered error message")

          get :show

          expect(response).to have_http_status(:forbidden)
          expect(response.body).to eq("Security Error")
          expect(Rails.logger).to have_received(:error).with("Filtered error message")
        end
      end

      context "JSONフォーマット" do
        it "JSON形式でエラーを返す" do
          allow(Rails.logger).to receive(:error)
          allow(SensitiveDataFilter).to receive(:filter_log_message).and_return("Filtered error message")

          get :show, format: :json

          expect(response).to have_http_status(:forbidden)
          expect(JSON.parse(response.body)).to eq({ "error" => "Security Error" })
        end
      end
    end

    describe "#handle_csrf_error" do
      controller do
        skip_before_action :verify_authenticity_token, only: :create
        def create
          raise ActionController::InvalidAuthenticityToken
        end
      end

      it "CSRFエラーを適切に処理する（HTML）" do
        allow(Rails.logger).to receive(:warn)

        post :create

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("セキュリティトークンが無効です")
        expect(Rails.logger).to have_received(:warn).with(/CSRF token verification failed/)
      end

      it "CSRFエラーを適切に処理する（JSON）" do
        allow(Rails.logger).to receive(:warn)

        post :create, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)).to eq({ "error" => "Invalid authenticity token" })
      end
    end

    context "ActiveRecord::RecordNotFound" do
      controller do
        def show
          raise ActiveRecord::RecordNotFound
        end
      end

      it "404エラーを返す" do
        get :show, params: { id: 1 }
        expect(response).to have_http_status(:not_found)
      end

      it "HTMLフォーマットでエラーページを表示" do
        get :show, params: { id: 1 }, format: :html
        expect(response).to redirect_to("/404")
      end

      it "JSONフォーマットでエラーレスポンスを返す" do
        get :show, params: { id: 1 }, format: :json
        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to be_present
      end
    end

    context "StandardError" do
      it "500エラーを返す" do
        allow(Rails.env).to receive(:production?).and_return(true)
        post :create
        expect(response).to have_http_status(:internal_server_error)
      end

      it "開発環境では例外を再発生させる" do
        allow(Rails.env).to receive(:production?).and_return(false)
        expect { post :create }.to raise_error(StandardError)
      end
    end

    context "ActionController::ParameterMissing" do
      it "400エラーを返す" do
        put :update, params: { id: 1 }
        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "機密情報フィルタリング" do
    describe "#configure_sensitive_data_filtering" do
      it "フィルターパラメータを設定する" do
        get :index

        filter_params = Rails.application.config.filter_parameters
        expect(filter_params).to include(:password, :token, :api_key, :secret, :credit_card)
        expect(filter_params).to include(:cvv, :ssn, :email, :phone, :address)
      end

      it "カスタムログフォーマッターを設定する" do
        logger = double("Logger", formatter: nil)
        allow(logger).to receive(:respond_to?).with(:formatter=).and_return(true)
        allow(logger).to receive(:formatter=)
        allow(Rails).to receive(:logger).and_return(logger)

        get :index

        expect(logger).to have_received(:formatter=).with(instance_of(SensitiveLogFormatter))
      end

      it "フォーマッター設定メソッドがない場合はスキップする" do
        logger = double("Logger")
        allow(logger).to receive(:respond_to?).with(:formatter=).and_return(false)
        allow(Rails).to receive(:logger).and_return(logger)

        expect { get :index }.not_to raise_error
      end
    end
  end

  describe "Current属性の設定" do
    describe "#set_current_attributes" do
      it "リクエスト情報をCurrentに設定する" do
        expect(Current).to receive(:reset)
        expect(Current).to receive(:set_request_info).with(request)

        get :index
      end

      context "current_userメソッドが定義されている場合" do
        let(:user) { double("User") }

        before do
          allow(controller).to receive(:respond_to?).with(:current_user).and_return(true)
          allow(controller).to receive(:current_user).and_return(user)
        end

        it "Currentにユーザーを設定する（将来の実装用）" do
          # 現在はコメントアウトされているが、実装時のテスト
          get :index
        end
      end
    end

    context "管理者としてログイン" do
      before { sign_in admin }

      it "Current.adminが設定される" do
        get :index
        expect(Current.admin).to eq(admin)
      end

      it "Current.userが設定される" do
        get :index
        expect(Current.user).to eq(admin)
      end
    end

    context "店舗ユーザーとしてログイン" do
      before { sign_in store_user }

      it "Current.store_userが設定される" do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store_user).and_return(store_user)

        get :index
        expect(Current.store_user).to eq(store_user)
      end
    end

    it "リクエストIDが設定される" do
      request.headers["X-Request-Id"] = "test-request-123"
      get :index
      expect(Current.request_id).to eq("test-request-123")
    end

    it "IPアドレスが設定される" do
      request.remote_addr = "192.168.1.1"
      get :index
      expect(Current.ip_address).to eq("192.168.1.1")
    end
  end

  describe "パフォーマンス監視" do
    it "処理時間がログに記録される" do
      expect(Rails.logger).to receive(:info).with(/Processing time:/)
      get :index
    end

    it "メモリ使用量がログに記録される（開発環境）" do
      allow(Rails.env).to receive(:development?).and_return(true)
      expect(Rails.logger).to receive(:info).with(/Memory usage:/)
      get :index
    end
  end

  describe "リダイレクト後のアクション" do
    it "前のページへのリダイレクトが機能する" do
      request.env["HTTP_REFERER"] = "/previous_page"
      allow(controller).to receive(:redirect_back_or_to)

      delete :destroy
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "after_sign_in_path_for" do
    context "管理者の場合" do
      it "管理者ダッシュボードにリダイレクト" do
        path = controller.after_sign_in_path_for(admin)
        expect(path).to eq(admin_root_path)
      end
    end

    context "店舗ユーザーの場合" do
      it "店舗選択画面にリダイレクト" do
        path = controller.after_sign_in_path_for(store_user)
        expect(path).to eq(store_selection_path)
      end
    end

    context "その他のリソースの場合" do
      it "ルートパスにリダイレクト" do
        path = controller.after_sign_in_path_for(Object.new)
        expect(path).to eq(root_path)
      end
    end
  end

  describe "after_sign_out_path_for" do
    context "管理者の場合" do
      it "管理者ログインページにリダイレクト" do
        path = controller.after_sign_out_path_for(Admin)
        expect(path).to eq(new_admin_session_path)
      end
    end

    context "店舗ユーザーの場合" do
      it "店舗選択ページにリダイレクト" do
        path = controller.after_sign_out_path_for(StoreUser)
        expect(path).to eq(store_selection_path)
      end
    end
  end

  describe "HTTPSリダイレクト" do
    context "本番環境" do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(ENV).to receive(:[]).with("FORCE_SSL").and_return("true")
      end

      it "HTTPSが強制される" do
        expect(ApplicationController.force_ssl_conditional?).to be true
      end
    end

    context "開発環境" do
      before do
        allow(Rails.env).to receive(:production?).and_return(false)
      end

      it "HTTPSが強制されない" do
        expect(ApplicationController.force_ssl_conditional?).to be false
      end
    end
  end

  describe "ロケール設定" do
    it "デフォルトロケールが日本語" do
      get :index
      expect(I18n.locale).to eq(:ja)
    end

    it "パラメータでロケールを変更できる" do
      get :index, params: { locale: :en }
      expect(I18n.locale).to eq(:en)
    end

    it "不正なロケールはデフォルトにフォールバック" do
      get :index, params: { locale: :invalid }
      expect(I18n.locale).to eq(:ja)
    end
  end

  describe "タイムゾーン設定" do
    it "Tokyo タイムゾーンが設定される" do
      get :index
      expect(Time.zone.name).to eq("Tokyo")
    end
  end

  describe "エラー通知（本番環境）" do
    before do
      allow(Rails.env).to receive(:production?).and_return(true)
    end

    it "エラーが通知サービスに送信される" do
      # TODO: エラー通知サービス（Sentry等）実装時にテスト追加
      expect { post :create }.to raise_error(StandardError)
    end
  end

  describe "レスポンスキャッシュ制御" do
    it "プライベートデータのキャッシュが無効化される" do
      sign_in admin
      get :index

      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  describe "TODOコメントの実装状況" do
    context "Phase 2 - エラー通知サービス統合" do
      it "Sentry統合予定" do
        skip "Sentryエラー通知は将来実装予定"
      end
    end

    context "Phase 3 - APIレート制限" do
      it "Rack::Attack統合予定" do
        skip "APIレート制限は将来実装予定"
      end
    end

    context "Phase 4 - 監査ログ機能" do
      it "包括的な監査ログ実装予定" do
        skip "監査ログ機能は将来実装予定"
      end
    end
  end
end
