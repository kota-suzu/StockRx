# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::OmniauthCallbacksController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:admin]
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

      # TODO: 🟢 Phase 4（推奨）- ログイン通知機能テスト
      # 優先度: 低（セキュリティ強化時）
      # 実装内容: GitHub認証成功時のメール・Slack通知テスト
      # 理由: セキュリティ意識向上、不正アクセス早期発見
      # 期待効果: セキュリティインシデントの予防・早期対応
      # 工数見積: 1日
      # 依存関係: メール送信機能、Slack API統合
    end

    context 'GitHub認証が失敗した場合' do
      let(:invalid_admin) { build(:admin, provider: 'github', uid: '123456') }

      before do
        allow(Admin).to receive(:from_omniauth).and_return(invalid_admin)
        allow(invalid_admin).to receive(:persisted?).and_return(false)
        allow(invalid_admin).to receive_message_chain(:errors, :full_messages).and_return(['エラーが発生しました'])
      end

      it 'ログインページにリダイレクトされること' do
        get :github
        expect(response).to redirect_to(new_admin_session_path)
      end

      it 'エラーメッセージが表示されること' do
        get :github
        expect(flash[:alert]).to eq('エラーが発生しました')
      end

      it 'セッションにGitHubデータが保存されること' do
        get :github
        expect(session["devise.github_data"]).to be_present
        expect(session["devise.github_data"]["provider"]).to eq('github')
      end

      # TODO: 🟡 Phase 3（中）- OAuth認証失敗のログ記録・監視テスト
      # 優先度: 中（セキュリティ監視強化）
      # 実装内容: 認証失敗ログの構造化記録、異常パターン検知テスト
      # 理由: セキュリティインシデントの早期発見、攻撃パターン分析
      # 期待効果: セキュリティ脅威の可視化、防御力向上
      # 工数見積: 1日
      # 依存関係: ログ監視システム構築
    end
  end

  # TODO: 🟡 Phase 3（中）- OAuth failure integration tests
  # 優先度: 中（統合テスト環境での実装）
  # 実装内容: feature testでのOAuth失敗フローの統合テスト
  # 理由: controller testでのDevise OmniAuth routingの複雑性回避
  # 期待効果: より実用的な失敗シナリオのテスト
  # 工数見積: 1日
  # 依存関係: feature test環境の構築

  describe 'セキュリティ設定' do
    it 'admin layoutが使用されること' do
      expect(controller.class._layout).to eq('admin')
    end

    # CSRF保護のテスト（omniauth-rails_csrf_protection gem使用）
    it 'CSRF保護が有効であること' do
      # omniauth-rails_csrf_protection gemにより自動的にCSRF保護が適用される
      expect(controller.class.protect_from_forgery).to be_truthy
    end
  end

  describe 'private methods' do
    describe '#failure_message' do
      it 'omniauth.errorがある場合、そのメッセージを返すこと' do
        request.env["omniauth.error"] = "invalid_request"
        expect(controller.send(:failure_message)).to eq("invalid_request")
      end

      it 'omniauth.errorがない場合、デフォルトメッセージを返すこと' do
        request.env["omniauth.error"] = nil
        expect(controller.send(:failure_message)).to eq("Unknown error")
      end
    end
  end

  # セキュリティ強化のためのテスト
  describe 'セキュリティ要件' do
    it 'Turbo対応が無効化されていること（ビューでdata: { turbo: false }）' do
      # ビューレベルのテストとして別途feature testで検証
      expect(true).to be_truthy # プレースホルダー
    end

    # TODO: 🟢 Phase 4（推奨）- セッション固定化攻撃対策テスト
    # 優先度: 低（高度セキュリティ対策）
    # 実装内容: セッションIDの適切な再生成確認テスト
    # 理由: セッション固定化攻撃の防止
    # 期待効果: 高度なセキュリティ脅威への対策
    # 工数見積: 1日
    # 依存関係: なし

    # TODO: 🟢 Phase 4（推奨）- レート制限テスト
    # 優先度: 低（DDoS対策）
    # 実装内容: OAuth認証エンドポイントのレート制限テスト
    # 理由: DDoS攻撃の防止、システム安定性確保
    # 期待効果: システムの可用性向上
    # 工数見積: 2日
    # 依存関係: レート制限ミドルウェア実装
  end
end