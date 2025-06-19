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
      store = create(:store)
      admin = build(:admin, store: store)
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
        store = create(:store)
        admin = build(:admin, store: store, password: 'Password123!', password_confirmation: 'Password123!')
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
      let(:oauth_admin) { build(:admin, provider: 'github', uid: '123', password: nil, password_confirmation: nil, role: 'headquarters_admin') }

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

  # ============================================
  # 🔴 Phase 1: Multi-Store Management Tests
  # ============================================

  describe 'multi-store associations' do
    # storeの関連付けは条件付き必須（headquarters_admin以外は必須）
    it 'has conditional store association' do
      # 本部管理者の場合はstore不要
      headquarters_admin = build(:admin, role: 'headquarters_admin', store: nil)
      expect(headquarters_admin).to be_valid

      # 店舗ユーザーの場合はstore必須
      store_user = build(:admin, role: 'store_user', store: nil)
      expect(store_user).not_to be_valid
      expect(store_user.errors[:store]).to include('本部管理者以外は店舗の指定が必要です')

      # 店舗ユーザーでstore指定があれば有効
      store = create(:store)
      store_user_with_store = build(:admin, role: 'store_user', store: store)
      expect(store_user_with_store).to be_valid
    end

    it { should have_many(:requested_transfers).class_name('InterStoreTransfer').with_foreign_key('requested_by_id') }
    it { should have_many(:approved_transfers).class_name('InterStoreTransfer').with_foreign_key('approved_by_id') }
  end

  describe 'multi-store validations' do
    it { should validate_presence_of(:role) }
    it { should validate_length_of(:name).is_at_most(50) }

    describe 'role-based store validation' do
      context 'non-headquarters admin' do
        %w[store_user pharmacist store_manager].each do |role|
          context "when role is #{role}" do
            let(:admin) { build(:admin, role: role, store: nil) }

            it 'requires store to be present' do
              expect(admin).not_to be_valid
              expect(admin.errors[:store]).to include('本部管理者以外は店舗の指定が必要です')
            end

            it 'is valid with store assigned' do
              admin.store = create(:store)
              expect(admin).to be_valid
            end
          end
        end
      end

      context 'headquarters admin' do
        let(:admin) { build(:admin, role: 'headquarters_admin', store: create(:store)) }

        it 'cannot have store assigned' do
          expect(admin).not_to be_valid
          expect(admin.errors[:store]).to include('本部管理者は特定の店舗に所属できません')
        end

        it 'is valid without store' do
          admin.store = nil
          expect(admin).to be_valid
        end
      end
    end
  end

  describe 'enums' do
    it { should define_enum_for(:role).backed_by_column_of_type(:string).with_values(
      store_user: 'store_user',
      pharmacist: 'pharmacist',
      store_manager: 'store_manager',
      headquarters_admin: 'headquarters_admin'
    ) }
  end

  describe 'scopes' do
    let!(:active_admin) { create(:admin, :store_user, active: true) }
    let!(:inactive_admin) { create(:admin, :store_user, active: false) }
    let!(:pharmacist) { create(:admin, :pharmacist) }
    let!(:store_manager) { create(:admin, :store_manager) }
    let!(:headquarters_admin) { create(:admin, :headquarters_admin) }
    let!(:store) { create(:store) }
    let!(:store_admin) { create(:admin, :store_user, store: store) }

    describe '.active' do
      it 'returns only active admins' do
        expect(Admin.active).to include(active_admin)
        expect(Admin.active).not_to include(inactive_admin)
      end
    end

    describe '.inactive' do
      it 'returns only inactive admins' do
        expect(Admin.inactive).to include(inactive_admin)
        expect(Admin.inactive).not_to include(active_admin)
      end
    end

    describe '.by_role' do
      it 'returns admins with specified role' do
        expect(Admin.by_role('pharmacist')).to include(pharmacist)
        expect(Admin.by_role('pharmacist')).not_to include(store_manager)
      end
    end

    describe '.by_store' do
      it 'returns admins for specified store' do
        expect(Admin.by_store(store)).to include(store_admin)
        expect(Admin.by_store(store)).not_to include(headquarters_admin)
      end
    end

    describe '.headquarters' do
      it 'returns only headquarters admins' do
        expect(Admin.headquarters).to include(headquarters_admin)
        expect(Admin.headquarters).not_to include(store_manager, pharmacist)
      end
    end

    describe '.store_staff' do
      it 'returns store-level staff (excluding headquarters)' do
        expect(Admin.store_staff).to include(pharmacist, store_manager, active_admin)
        expect(Admin.store_staff).not_to include(headquarters_admin)
      end
    end
  end

  describe '#display_name' do
    context 'when name field is present' do
      let(:admin) { build(:admin, name: '田中太郎', email: 'tanaka@example.com') }

      it 'returns the name field value' do
        expect(admin.display_name).to eq('田中太郎')
      end
    end

    context 'when name field is blank' do
      let(:admin) { build(:admin, name: '', email: 'john.doe@example.com') }

      it 'returns email prefix as fallback' do
        expect(admin.display_name).to eq('john.doe')
      end
    end

    context 'when name field is nil' do
      let(:admin) { build(:admin, name: nil, email: 'admin@example.com') }

      it 'returns email prefix as fallback' do
        expect(admin.display_name).to eq('admin')
      end
    end

    context 'complex email format' do
      let(:admin) { build(:admin, name: nil, email: 'admin+test@sub.example.com') }

      it 'correctly extracts display name from email' do
        expect(admin.display_name).to eq('admin+test')
      end
    end
  end

  describe '#role_text' do
    it 'returns Japanese text for each role' do
      role_translations = {
        'store_user' => '店舗ユーザー',
        'pharmacist' => '薬剤師',
        'store_manager' => '店舗管理者',
        'headquarters_admin' => '本部管理者'
      }

      role_translations.each do |role, text|
        admin = build(:admin, role: role)
        expect(admin.role_text).to eq(text)
      end
    end
  end

  describe 'permission methods' do
    let(:store1) { create(:store) }
    let(:store2) { create(:store) }

    describe '#can_access_all_stores?' do
      it 'returns true for headquarters admin' do
        admin = build(:admin, :headquarters_admin)
        expect(admin.can_access_all_stores?).to be true
      end

      it 'returns false for store-level roles' do
        %w[store_user pharmacist store_manager].each do |role|
          admin = build(:admin, role: role, store: store1)
          expect(admin.can_access_all_stores?).to be false
        end
      end
    end

    describe '#can_manage_store?' do
      it 'allows headquarters admin to manage any store' do
        admin = build(:admin, :headquarters_admin)
        expect(admin.can_manage_store?(store1)).to be true
        expect(admin.can_manage_store?(store2)).to be true
      end

      it 'allows store manager to manage their own store' do
        admin = build(:admin, :store_manager, store: store1)
        expect(admin.can_manage_store?(store1)).to be true
        expect(admin.can_manage_store?(store2)).to be false
      end

      it 'denies store users and pharmacists from managing stores' do
        %w[store_user pharmacist].each do |role|
          admin = build(:admin, role: role, store: store1)
          expect(admin.can_manage_store?(store1)).to be false
          expect(admin.can_manage_store?(store2)).to be false
        end
      end
    end

    describe '#can_approve_transfers?' do
      it 'allows store managers and headquarters admins to approve transfers' do
        %w[store_manager headquarters_admin].each do |role|
          admin = build(:admin, role: role)
          expect(admin.can_approve_transfers?).to be true
        end
      end

      it 'denies store users and pharmacists from approving transfers' do
        %w[store_user pharmacist].each do |role|
          admin = build(:admin, role: role, store: store1)
          expect(admin.can_approve_transfers?).to be false
        end
      end
    end

    describe '#can_view_store?' do
      it 'allows headquarters admin to view any store' do
        admin = build(:admin, :headquarters_admin)
        expect(admin.can_view_store?(store1)).to be true
        expect(admin.can_view_store?(store2)).to be true
      end

      it 'allows store staff to view only their assigned store' do
        %w[store_user pharmacist store_manager].each do |role|
          admin = build(:admin, role: role, store: store1)
          expect(admin.can_view_store?(store1)).to be true
          expect(admin.can_view_store?(store2)).to be false
        end
      end
    end

    describe '#accessible_store_ids' do
      before do
        create_list(:store, 3, active: true)
        create(:store, active: false) # inactive store should be excluded
      end

      it 'returns all active store IDs for headquarters admin' do
        admin = build(:admin, :headquarters_admin)
        expect(admin.accessible_store_ids).to match_array(Store.active.pluck(:id))
      end

      it 'returns only assigned store ID for store staff' do
        admin = build(:admin, :store_user, store: store1)
        expect(admin.accessible_store_ids).to eq([ store1.id ])
      end

      it 'returns empty array when no store assigned' do
        admin = build(:admin, :headquarters_admin, store: nil)
        admin.role = 'store_user' # This would be invalid, but testing the method logic
        admin.store = nil
        expect(admin.accessible_store_ids).to eq([])
      end
    end

    describe '#manageable_stores' do
      before do
        create_list(:store, 2, active: true)
        create(:store, active: false) # inactive store should be excluded
      end

      it 'returns all active stores for headquarters admin' do
        admin = build(:admin, :headquarters_admin)
        expect(admin.manageable_stores).to match_array(Store.active)
      end

      it 'returns assigned store for store manager' do
        admin = build(:admin, :store_manager, store: store1)
        expect(admin.manageable_stores).to eq([ store1 ])
      end

      it 'returns no stores for store users and pharmacists' do
        %w[store_user pharmacist].each do |role|
          admin = build(:admin, role: role, store: store1)
          expect(admin.manageable_stores).to eq(Admin.none)
        end
      end

      it 'returns no stores for store manager without assigned store' do
        admin = build(:admin, :store_manager, store: nil)
        expect(admin.manageable_stores).to eq(Admin.none)
      end
    end
  end

  # TODO: Phase 2以降で実装予定のテスト
  #
  # 🔴 Phase 2 優先実装項目:
  # 1. 店舗間移動申請・承認ワークフローテスト
  #    - requested_transfers/approved_transfersアソシエーション
  #    - 承認権限による移動申請処理フロー
  #    - 権限レベル別の操作制限確認
  #    期待効果: 安全で効率的な移動承認プロセス
  #
  # 2. 管理者通知機能テスト
  #    - 移動申請・承認・完了時の通知送信
  #    - 役割別通知設定（store_manager vs headquarters_admin）
  #    - メール・管理画面通知の配信確認
  #    期待効果: リアルタイムな情報共有とワークフロー促進
  #
  # 🟡 Phase 3 重要実装項目:
  # 3. 詳細権限管理テスト
  #    - 権限レベル（admin/super_admin）による機能制限
  #    - リソースレベルでのアクセス制御
  #    - 監査ログ・アクセス履歴記録
  #    期待効果: 細かい権限制御による安全性向上
  #
  # 4. GitHub OAuth高度機能テスト
  #    - GitHub組織メンバーシップ連携
  #    - 自動権限付与・役割マッピング
  #    - OAuth認証ログ・監査機能
  #    期待効果: 組織管理との自動連携
  #
  # 🟢 Phase 4 推奨実装項目:
  # 5. 2要素認証機能テスト
  #    - devise-two-factor統合テスト
  #    - QRコード生成・TOTPワンタイムパスワード
  #    - バックアップコード・復旧プロセス
  #    期待効果: セキュリティレベル大幅向上
  #
  # 6. ユーザーモデル連携テスト
  #    - 一般スタッフ向けUserモデル統合
  #    - 管理者によるユーザーアカウント管理
  #    - 階層的権限管理（Admin > User）
  #    期待効果: 包括的なアクセス管理システム
end
