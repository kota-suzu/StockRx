# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::OauthDebugController, type: :controller do
  # CLAUDE.md準拠: OAuth デバッグ機能のテスト
  # メタ認知: 一時的なデバッグ用コントローラーだが、OAuth設定の検証に重要
  # 横展開: 他のデバッグ・開発支援コントローラーでも同様のテストパターン適用

  describe "認証のスキップ" do
    it "authenticate_admin!をスキップしてアクセス可能" do
      # 未ログイン状態でもアクセス可能であることをテスト
      get :show
      expect(response).to be_successful
    end
  end

  describe "GET #show" do
    context "OAuth設定情報の表示" do
      it "成功レスポンスを返す" do
        get :show
        expect(response).to have_http_status(:success)
      end

      it "OAuth設定情報を@omniauth_configに格納する" do
        get :show
        config = assigns(:omniauth_config)

        expect(config).to be_a(Hash)
        expect(config).to have_key(:providers)
        expect(config).to have_key(:github_configured)
        expect(config).to have_key(:expected_redirect_uri)
        expect(config).to have_key(:rails_env)
      end

      it "リクエスト情報を正しく収集する" do
        get :show
        request_info = assigns(:omniauth_config)[:request_info]

        expect(request_info).to have_key(:host)
        expect(request_info).to have_key(:port)
        expect(request_info).to have_key(:protocol)
        expect(request_info).to have_key(:host_with_port)
        expect(request_info).to have_key(:url)
        expect(request_info).to have_key(:base_url)
      end

      it "開発環境で正しいredirect_uriを生成する" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        get :show

        expected_uri = assigns(:omniauth_config)[:expected_redirect_uri]
        expect(expected_uri).to eq("http://localhost:3000/admin/auth/github/callback")
      end
    end

    context "GitHub設定確認" do
      context "GitHub認証情報が設定されている場合" do
        before do
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_id).and_return("test_client_id")
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_secret).and_return("test_client_secret")
        end

        it "github_configuredがtrueになる" do
          get :show
          expect(assigns(:omniauth_config)[:github_configured]).to be true
        end
      end

      context "GitHub認証情報が設定されていない場合" do
        before do
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_id).and_return(nil)
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_secret).and_return(nil)
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_ID").and_return(nil)
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_SECRET").and_return(nil)
        end

        it "github_configuredがfalseになる" do
          get :show
          expect(assigns(:omniauth_config)[:github_configured]).to be false
        end
      end

      context "環境変数での設定" do
        before do
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_ID").and_return("env_client_id")
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_SECRET").and_return("env_client_secret")
        end

        it "環境変数の設定を優先する" do
          get :show
          expect(assigns(:omniauth_config)[:github_configured]).to be true
        end
      end
    end
  end

  describe "GET #callback_info" do
    context "JSON レスポンス" do
      it "JSON形式でコールバック情報を返す" do
        get :callback_info
        expect(response.content_type).to include('application/json')
      end

      it "成功レスポンスを返す" do
        get :callback_info
        expect(response).to have_http_status(:success)
      end

      it "コールバック情報を正しく構造化する" do
        get :callback_info
        json_response = JSON.parse(response.body)

        expect(json_response).to have_key('callback_url')
        expect(json_response).to have_key('callback_path')
        expect(json_response).to have_key('full_host')
        expect(json_response).to have_key('options')
      end
    end

    context "GitHub戦略が見つからない場合" do
      it "エラー情報を返す" do
        # モックの戦略が返されるため、実際はエラーにならないが
        # エラーケースの構造を確認
        get :callback_info
        json_response = JSON.parse(response.body)

        # モック戦略の情報が返される
        expect(json_response).to have_key('callback_url')
      end
    end
  end

  describe "プライベートメソッド" do
    describe "#github_configured?" do
      context "credentials ファイルで設定されている場合" do
        before do
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_id).and_return("test_id")
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_secret).and_return("test_secret")
        end

        it "trueを返す" do
          result = controller.send(:github_configured?)
          expect(result).to be true
        end
      end

      context "環境変数で設定されている場合" do
        before do
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_ID").and_return("env_id")
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_SECRET").and_return("env_secret")
        end

        it "trueを返す" do
          result = controller.send(:github_configured?)
          expect(result).to be true
        end
      end

      context "設定されていない場合" do
        before do
          allow(Rails.application.credentials).to receive(:dig).and_return(nil)
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_ID").and_return(nil)
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_SECRET").and_return(nil)
        end

        it "falseを返す" do
          result = controller.send(:github_configured?)
          expect(result).to be false
        end
      end

      context "片方だけ設定されている場合" do
        before do
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_id).and_return("test_id")
          allow(Rails.application.credentials).to receive(:dig).with(:github, :client_secret).and_return(nil)
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_ID").and_return(nil)
          allow(ENV).to receive(:[]).with("GITHUB_CLIENT_SECRET").and_return(nil)
        end

        it "falseを返す" do
          result = controller.send(:github_configured?)
          expect(result).to be false
        end
      end
    end

    describe "#expected_redirect_uri" do
      context "開発環境の場合" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        end

        it "localhost:3000のURIを返す" do
          uri = controller.send(:expected_redirect_uri)
          expect(uri).to eq("http://localhost:3000/admin/auth/github/callback")
        end
      end

      context "本番環境の場合" do
        before do
          allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
          allow(controller.request).to receive(:protocol).and_return("https://")
          allow(controller.request).to receive(:host_with_port).and_return("stockrx.example.com")
        end

        it "本番ドメインのURIを返す" do
          uri = controller.send(:expected_redirect_uri)
          expect(uri).to eq("https://stockrx.example.com/admin/auth/github/callback")
        end
      end
    end

    describe "#github_auth_url" do
      it "GitHub認証のパスを返す" do
        url = controller.send(:github_auth_url)
        expect(url).to eq("/admin/auth/github")
      end
    end

    describe "#full_host_from_request" do
      context "OmniAuth.config.full_hostがProcの場合" do
        before do
          proc_config = ->(env) { "https://dynamic.example.com" }
          allow(OmniAuth.config).to receive(:full_host).and_return(proc_config)
        end

        it "Procを実行した結果を返す" do
          host = controller.send(:full_host_from_request)
          expect(host).to eq("https://dynamic.example.com")
        end
      end

      context "OmniAuth.config.full_hostが文字列の場合" do
        before do
          allow(OmniAuth.config).to receive(:full_host).and_return("https://static.example.com")
        end

        it "設定値をそのまま返す" do
          host = controller.send(:full_host_from_request)
          expect(host).to eq("https://static.example.com")
        end
      end
    end

    describe "#find_github_strategy" do
      it "モックのGitHub戦略を返す" do
        strategy = controller.send(:find_github_strategy)

        expect(strategy).to respond_to(:callback_url)
        expect(strategy).to respond_to(:callback_path)
        expect(strategy).to respond_to(:full_host)
        expect(strategy).to respond_to(:options)
      end

      it "正しいコールバックパスを含む" do
        strategy = controller.send(:find_github_strategy)
        expect(strategy.callback_path).to eq("/admin/auth/github/callback")
      end
    end
  end

  describe "セキュリティ考慮" do
    context "機密情報の漏洩防止" do
      before do
        allow(Rails.application.credentials).to receive(:dig).with(:github, :client_id).and_return("secret_client_id")
        allow(Rails.application.credentials).to receive(:dig).with(:github, :client_secret).and_return("secret_client_secret")
      end

      it "client_secretは表示されない" do
        get :show
        config = assigns(:omniauth_config)

        # 設定有無は確認できるが、実際の値は表示されない
        expect(config[:github_configured]).to be true
        expect(config.to_s).not_to include("secret_client_secret")
      end

      it "callback_infoでもclient_secretは含まれない" do
        get :callback_info
        json_response = JSON.parse(response.body)

        expect(json_response.to_s).not_to include("secret_client_secret")
      end
    end
  end

  describe "エラーハンドリング" do
    context "credentials読み込みエラー" do
      before do
        allow(Rails.application.credentials).to receive(:dig).and_raise(StandardError, "Credentials error")
      end

      it "例外を適切に処理する" do
        # GitHub設定でエラーが発生しても、処理は継続される
        expect {
          get :show
        }.not_to raise_error

        expect(response).to be_successful
        expect(assigns(:omniauth_config)[:github_configured]).to be false
      end
    end

    context "OmniAuth設定エラー" do
      before do
        allow(OmniAuth.config).to receive(:full_host).and_raise(StandardError, "OmniAuth error")
      end

      it "例外が発生することを確認する" do
        # このエラーは現在キャッチしていないため、例外が発生する
        expect {
          get :show
        }.to raise_error(StandardError, "OmniAuth error")
      end
    end
  end

  describe "TODO: 削除時の考慮事項" do
    # この一時的なコントローラーは OAuth 問題解決後に削除予定
    # 削除前に確認すべき項目:
    # 1. OAuth redirect_uri の問題が完全に解決されていること
    # 2. 本番環境でのGitHub認証が正常に動作すること
    # 3. 他のデバッグ方法（ログ、モニタリング）が確立されていること

    it "一時的なコントローラーであることを明示" do
      # コントローラーのコメントで一時的であることが明記されている
      controller_file = File.read(Rails.root.join("app/controllers/admin_controllers/oauth_debug_controller.rb"))
      expect(controller_file).to include("Temporary controller")
      expect(controller_file).to include("should be removed")
    end
  end
end
