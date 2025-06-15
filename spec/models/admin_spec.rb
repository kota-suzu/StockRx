# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Admin, type: :model do
  describe 'Devise設定' do
    it { should be_a(Devise::Models::DatabaseAuthenticatable) }
    it { should be_a(Devise::Models::Recoverable) }
    it { should be_a(Devise::Models::Rememberable) }
    it { should be_a(Devise::Models::Validatable) }
    it { should be_a(Devise::Models::Lockable) }
    it { should be_a(Devise::Models::Timeoutable) }
    it { should be_a(Devise::Models::Trackable) }
    it { should be_a(Devise::Models::Omniauthable) }

    it 'GitHub OmniAuthプロバイダーが設定されていること' do
      expect(Admin.omniauth_providers).to include(:github)
    end
  end

  describe 'ファクトリー' do
    it '有効なファクトリーが作成できること' do
      admin = build(:admin)
      expect(admin).to be_valid
    end
  end

  describe 'バリデーション' do
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }

    context 'パスワード強度チェック' do
      it '弱いパスワードは無効であること' do
        admin = build(:admin, password: 'password', password_confirmation: 'password')
        expect(admin).not_to be_valid
        expect(admin.errors[:password]).to include(/大文字を含める/)
      end

      it '強いパスワードは有効であること' do
        admin = build(:admin, password: 'Password123!', password_confirmation: 'Password123!')
        expect(admin).to be_valid
      end
    end
  end

  describe '#from_omniauth' do
    let(:auth_hash) do
      OmniAuth::AuthHash.new({
        provider: 'github',
        uid: '123456',
        info: {
          email: 'github-user@example.com'
        },
        extra: {
          raw_info: {
            ip: '192.168.1.1'
          }
        }
      })
    end

    context '新規GitHubユーザーの場合' do
      it '新しい管理者アカウントが作成されること' do
        expect {
          Admin.from_omniauth(auth_hash)
        }.to change(Admin, :count).by(1)
      end

      it '適切な属性が設定されること' do
        admin = Admin.from_omniauth(auth_hash)

        expect(admin.provider).to eq('github')
        expect(admin.uid).to eq('123456')
        expect(admin.email).to eq('github-user@example.com')
        expect(admin.sign_in_count).to eq(1)
        expect(admin.current_sign_in_ip).to eq('192.168.1.1')
        expect(admin).to be_persisted
      end

      it 'ランダムパスワードが設定されること' do
        admin = Admin.from_omniauth(auth_hash)
        expect(admin.encrypted_password).to be_present
      end
    end

    context '既存GitHubユーザーの場合' do
      let!(:existing_admin) do
        create(:admin, provider: 'github', uid: '123456',
               email: 'old-email@example.com', sign_in_count: 5)
      end

      it '新しいアカウントは作成されないこと' do
        expect {
          Admin.from_omniauth(auth_hash)
        }.not_to change(Admin, :count)
      end

      it '既存アカウントの情報が更新されること' do
        admin = Admin.from_omniauth(auth_hash)

        expect(admin.id).to eq(existing_admin.id)
        expect(admin.email).to eq('github-user@example.com')
        expect(admin.sign_in_count).to eq(6)
        expect(admin.current_sign_in_ip).to eq('192.168.1.1')
      end
    end

    context 'IPアドレス情報がない場合' do
      let(:auth_hash_no_ip) do
        OmniAuth::AuthHash.new({
          provider: 'github',
          uid: '789',
          info: { email: 'no-ip@example.com' }
        })
      end

      it 'デフォルトIPアドレスが設定されること' do
        admin = Admin.from_omniauth(auth_hash_no_ip)
        expect(admin.current_sign_in_ip).to eq('127.0.0.1')
      end
    end
  end

  describe 'OAuthユーザーのパスワードバリデーション' do
    context 'providerとuidが存在する場合' do
      let(:oauth_admin) { build(:admin, provider: 'github', uid: '123', password: nil, password_confirmation: nil) }

      it 'パスワードバリデーションがスキップされること' do
        expect(oauth_admin).to be_valid
        expect(oauth_admin.send(:password_required?)).to be_falsey
        expect(oauth_admin.send(:password_required_for_validation?)).to be_falsey
      end
    end

    context 'providerとuidが存在しない場合' do
      let(:regular_admin) { build(:admin, provider: nil, uid: nil, password: 'weak') }

      it 'パスワードバリデーションが実行されること' do
        expect(regular_admin).not_to be_valid
        expect(regular_admin.send(:password_required?)).to be_truthy
        expect(regular_admin.send(:password_required_for_validation?)).to be_truthy
      end
    end

    context 'OAuthユーザーで既存のものを更新する場合' do
      let(:oauth_admin) { create(:admin, provider: 'github', uid: '456', email: 'oauth@example.com') }

      it 'パスワード変更なしで更新できること' do
        oauth_admin.email = 'new-oauth@example.com'
        expect(oauth_admin).to be_valid
        expect(oauth_admin.save).to be_truthy
      end
    end
  end

  describe '#display_name と #name メソッド' do
    let(:admin) { build(:admin, email: 'john.doe@example.com') }

    describe '#display_name' do
      it 'emailのアットマーク前の部分を返すこと' do
        expect(admin.display_name).to eq('john.doe')
      end

      context 'emailが複雑な形式の場合' do
        let(:admin) { build(:admin, email: 'admin+test@sub.example.com') }

        it '正しく表示名を抽出すること' do
          expect(admin.display_name).to eq('admin+test')
        end
      end

      context 'emailがシンプルな形式の場合' do
        let(:admin) { build(:admin, email: 'admin@example.com') }

        it '正しく表示名を抽出すること' do
          expect(admin.display_name).to eq('admin')
        end
      end
    end

    describe '#name' do
      it 'display_nameと同じ値を返すこと（エイリアス）' do
        expect(admin.name).to eq(admin.display_name)
        expect(admin.name).to eq('john.doe')
      end
    end

    # TODO: 🟡 Phase 2 - nameフィールド実装後のテスト
    # 優先度: 中（UX改善）
    # テスト内容:
    #   - nameカラムが存在する場合の動作確認
    #   - nameが空の場合のフォールバック処理
    #   - GitHub OAuth認証時のname自動設定
    # 期待効果: 適切な表示名管理によるUX向上
  end

  # TODO: 将来実装予定の機能テスト
  # 1. Userモデルとの連携（ユーザーの作成・管理権限）
  # 2. 2要素認証（devise-two-factor）
  # 3. 権限レベル（admin/super_admin）による機能制限
  # 4. 🟡 Phase 3（中）- GitHub管理者の自動承認・権限設定テスト
  # 5. 🟢 Phase 4（推奨）- ログイン通知機能テスト
end
