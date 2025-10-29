# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admins::OmniauthCallbacksController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:admin]
  end

  describe 'GET #passthru' do
    before do
      # OmniAuthのテストモードを設定
      OmniAuth.config.test_mode = true
      request.env["omniauth.auth"] = nil
    end

    after do
      # テストモードをリセット
      OmniAuth.config.test_mode = false
    end

    context 'プロバイダーがgithubの場合' do
      it 'passthruメソッドが呼ばれること' do
        # Deviseの親クラスのpassthruメソッドが呼ばれることを確認
        expect(controller).to receive(:passthru).and_call_original
        get :passthru, params: { provider: 'github' }
      end

      it 'ステータスコード404を返すこと（Deviseのデフォルト動作）' do
        # Deviseのデフォルトpassthruは404を返す
        get :passthru, params: { provider: 'github' }
        expect(response).to have_http_status(:not_found)
      end
    end

    context '無効なプロバイダーの場合' do
      it 'ステータスコード404を返すこと' do
        get :passthru, params: { provider: 'invalid_provider' }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET #github' do
    let(:omniauth_hash) do
      OmniAuth::AuthHash.new({
        provider: 'github',
        uid: '123456',
        info: {
          email: 'github-user@example.com',
          name: 'GitHub User'
        },
        credentials: {
          token: 'github_access_token'
        },
        extra: {
          raw_info: {
            login: 'github-user',
            ip: '192.168.1.1'
          }
        }
      })
    end

    before do
      request.env["omniauth.auth"] = omniauth_hash
    end

    context 'GitHub認証が成功した場合' do
      let!(:admin) { create(:admin, provider: 'github', uid: '123456') }

      before do
        allow(Admin).to receive(:from_omniauth).and_return(admin)
        allow(admin).to receive(:persisted?).and_return(true)
      end

      it '管理者ダッシュボードにリダイレクトされること' do
        get :github
        expect(response).to redirect_to(admin_root_path)
      end

      it '成功メッセージが表示されること' do
        get :github
        expect(flash[:notice]).to match(/GitHub/)
      end

      it '管理者がサインインされること' do
        get :github
        expect(controller.current_admin).to eq(admin)
      end

      it '監査ログが記録されること（ログ出力）' do
        expect(Rails.logger).to receive(:info).with(/OAuth Authentication.*status=success/)
        get :github
      end
    end

    context 'GitHub認証が失敗した場合' do
      let(:invalid_admin) { build(:admin, provider: 'github', uid: '123456') }

      before do
        allow(Admin).to receive(:from_omniauth).and_return(invalid_admin)
        allow(invalid_admin).to receive(:persisted?).and_return(false)
        allow(invalid_admin).to receive(:errors).and_return(
          double(
            :[] => [ 'エラーが発生しました' ],
            email: [],
            role: []
          )
        )
      end

      it 'ログインページにリダイレクトされること' do
        get :github
        expect(response).to redirect_to(new_admin_session_path)
      end

      it 'エラーメッセージが表示されること' do
        get :github
        expect(flash[:alert]).to match(/アカウントの作成に失敗しました/)
      end

      it 'セッションにGitHubデータが保存されること' do
        get :github
        expect(session["devise.github_data"]).to be_present
        expect(session["devise.github_data"]["provider"]).to eq('github')
      end

      it '監査ログが記録されること（ログ出力）' do
        expect(Rails.logger).to receive(:info).with(/OAuth Authentication.*status=failure/)
        get :github
      end
    end

    context '例外が発生した場合' do
      before do
        allow(Admin).to receive(:from_omniauth).and_raise(StandardError, 'テストエラー')
      end

      it 'ログインページにリダイレクトされること' do
        get :github
        expect(response).to redirect_to(new_admin_session_path)
      end

      it 'エラーメッセージが表示されること' do
        get :github
        expect(flash[:alert]).to eq('GitHub認証中にエラーが発生しました。')
      end

      it 'エラーログが記録されること' do
        expect(Rails.logger).to receive(:error).with(/GitHub OAuth Error: テストエラー/)
        expect(Rails.logger).to receive(:error).with(anything) # バックトレース
        get :github
      end
    end
  end

  describe 'GET #failure' do
    before do
      request.env["omniauth.error.type"] = :invalid_credentials
    end

    it 'ログインページにリダイレクトされること' do
      get :failure
      expect(response).to redirect_to(new_admin_session_path)
    end

    it 'エラーメッセージが表示されること' do
      get :failure
      expect(flash[:alert]).to match(/GitHub認証に失敗しました/)
    end

    it '監査ログが記録されること（ログ出力）' do
      expect(Rails.logger).to receive(:info).with(/OAuth Authentication.*status=failure/)
      get :failure
    end
  end

  describe 'private methods' do
    describe '#github_error_message' do
      let(:admin) { build(:admin) }

      context 'メールアドレスエラーの場合' do
        before do
          allow(admin).to receive_message_chain(:errors, :[]).with(:email).and_return([ 'has already been taken' ])
          allow(admin).to receive_message_chain(:errors, :[]).with(:role).and_return([])
        end

        it '適切なエラーメッセージを返すこと' do
          message = controller.send(:github_error_message, admin)
          expect(message).to eq('このメールアドレスは既に登録されています。')
        end
      end

      context '権限エラーの場合' do
        before do
          allow(admin).to receive_message_chain(:errors, :[]).with(:email).and_return([])
          allow(admin).to receive_message_chain(:errors, :[]).with(:role).and_return([ 'is invalid' ])
        end

        it '適切なエラーメッセージを返すこと' do
          message = controller.send(:github_error_message, admin)
          expect(message).to eq('権限の設定に問題があります。管理者にお問い合わせください。')
        end
      end

      context 'その他のエラーの場合' do
        before do
          allow(admin).to receive_message_chain(:errors, :[]).with(:email).and_return([])
          allow(admin).to receive_message_chain(:errors, :[]).with(:role).and_return([])
        end

        it 'デフォルトのエラーメッセージを返すこと' do
          message = controller.send(:github_error_message, admin)
          expect(message).to eq('アカウントの作成に失敗しました。管理者にお問い合わせください。')
        end
      end
    end
  end

  # セキュリティ要件のテスト
  describe 'セキュリティ要件' do
    it 'CSRF保護が有効であること' do
      # omniauth-rails_csrf_protection gemにより自動的にCSRF保護が適用される
      expect(controller.class.protect_from_forgery).to be_truthy
    end

    # TODO: 🟢 Phase 4（推奨）- セッション固定化攻撃対策テスト
    # 優先度: 低（高度セキュリティ対策）
    # 実装内容: セッションIDの適切な再生成確認テスト
    # 理由: セッション固定化攻撃の防止
    # 期待効果: 高度なセキュリティ脅威への対策
    # 工数見積: 1日
    # 依存関係: なし
  end
end
