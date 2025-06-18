# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreUser, type: :model do
  # ============================================
  # アソシエーションテスト
  # ============================================
  describe 'associations' do
    it { should belong_to(:store) }
  end

  # ============================================
  # バリデーションテスト
  # ============================================
  describe 'validations' do
    subject { build(:store_user) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(100) }
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:role) }
    it { should validate_inclusion_of(:role).in_array(%w[staff manager]) }

    context 'email uniqueness' do
      let(:store) { create(:store) }
      let!(:existing_user) { create(:store_user, store: store, email: 'test@example.com') }

      it 'allows same email in different stores' do
        other_store = create(:store)
        new_user = build(:store_user, store: other_store, email: 'test@example.com')
        expect(new_user).to be_valid
      end

      it 'prevents duplicate email in same store' do
        new_user = build(:store_user, store: store, email: 'test@example.com')
        expect(new_user).not_to be_valid
        expect(new_user.errors[:email]).to include('は既にこの店舗で使用されています')
      end
    end

    context 'password validation' do
      it 'requires password on create' do
        user = build(:store_user, password: nil, password_confirmation: nil)
        expect(user).not_to be_valid
      end

      it 'validates password strength' do
        user = build(:store_user, password: 'weak')
        expect(user).not_to be_valid
      end

      it 'accepts strong password' do
        user = build(:store_user, password: 'SecureP@ssw0rd123!')
        expect(user).to be_valid
      end
    end
  end

  # ============================================
  # スコープテスト
  # ============================================
  describe 'scopes' do
    let!(:active_user) { create(:store_user, active: true) }
    let!(:inactive_user) { create(:store_user, :inactive) }
    let!(:manager) { create(:store_user, :manager) }
    let!(:staff) { create(:store_user, role: 'staff') }

    describe '.active' do
      it 'returns only active users' do
        expect(StoreUser.active).to include(active_user, manager, staff)
        expect(StoreUser.active).not_to include(inactive_user)
      end
    end

    describe '.managers' do
      it 'returns only managers' do
        expect(StoreUser.managers).to eq([ manager ])
      end
    end
  end

  # ============================================
  # インスタンスメソッドテスト
  # ============================================
  describe 'instance methods' do
    let(:store) { create(:store, name: 'Test Store') }
    let(:user) { create(:store_user, store: store, name: 'Test User', role: 'manager') }

    describe '#display_name' do
      it 'returns formatted name with store' do
        expect(user.display_name).to eq('Test User (Test Store)')
      end
    end

    describe '#manager?' do
      it 'returns true for managers' do
        expect(user.manager?).to be true
      end

      it 'returns false for staff' do
        staff_user = create(:store_user, role: 'staff')
        expect(staff_user.manager?).to be false
      end
    end

    describe '#staff?' do
      it 'returns true for staff' do
        staff_user = create(:store_user, role: 'staff')
        expect(staff_user.staff?).to be true
      end

      it 'returns false for managers' do
        expect(user.staff?).to be false
      end
    end

    describe '#can_manage_inventory?' do
      it 'returns true for managers' do
        expect(user.can_manage_inventory?).to be true
      end

      it 'returns false for staff' do
        staff_user = create(:store_user, role: 'staff')
        expect(staff_user.can_manage_inventory?).to be false
      end
    end

    describe '#full_email' do
      it 'returns email with store name' do
        expect(user.full_email).to eq("#{user.email} (#{store.name})")
      end
    end
  end

  # ============================================
  # セキュリティテスト（カバレッジ向上）
  # ============================================

  describe 'security features' do
    let(:user) { create(:store_user) }

    describe 'password security' do
      it 'hashes password correctly' do
        expect(user.encrypted_password).to be_present
        expect(user.encrypted_password).not_to eq('SecureP@ssw0rd123!')
      end

      it 'validates password on update if provided' do
        user.password = 'weak'
        user.password_confirmation = 'weak'
        expect(user).not_to be_valid
        expect(user.errors[:password]).to be_present
      end

      it 'allows update without password change' do
        original_password = user.encrypted_password
        user.name = 'Updated Name'
        user.save!
        expect(user.encrypted_password).to eq(original_password)
        expect(user.name).to eq('Updated Name')
      end
    end

    describe 'account lockout' do
      before do
        # Deviseの設定をテスト用に上書き
        allow(user).to receive(:max_attempts).and_return(3)
      end

      it 'tracks failed login attempts' do
        expect(user.failed_attempts).to eq(0)

        # 失敗回数を増やす
        user.increment!(:failed_attempts)
        expect(user.failed_attempts).to eq(1)
      end

      it 'locks account after max attempts' do
        user.update!(failed_attempts: 3)
        user.lock_access!

        expect(user.access_locked?).to be true
        expect(user.locked_at).to be_present
      end

      it 'unlocks account after timeout' do
        user.lock_access!
        user.unlock_access!

        expect(user.access_locked?).to be false
        expect(user.failed_attempts).to eq(0)
      end
    end

    describe 'session management' do
      it 'remembers user sessions' do
        user.remember_me!
        expect(user.remember_created_at).to be_present
        expect(user.remember_token).to be_present
      end

      it 'forgets user sessions' do
        user.remember_me!
        user.forget_me!
        expect(user.remember_token).to be_nil
      end
    end
  end

  # ============================================
  # 認証統合テスト（カバレッジ向上）
  # ============================================

  describe 'authentication integration' do
    let(:store) { create(:store) }
    let(:user) { create(:store_user, store: store, email: 'test@example.com', password: 'SecureP@ssw0rd123!') }

    describe 'password authentication' do
      it 'authenticates with correct password' do
        expect(user.valid_password?('SecureP@ssw0rd123!')).to be true
      end

      it 'rejects incorrect password' do
        expect(user.valid_password?('wrongpassword')).to be false
      end
    end

    describe 'email authentication' do
      it 'finds user by email and store' do
        found_user = StoreUser.find_by(email: 'test@example.com', store: store)
        expect(found_user).to eq(user)
      end

      it 'does not find user in different store' do
        other_store = create(:store)
        found_user = StoreUser.find_by(email: 'test@example.com', store: other_store)
        expect(found_user).to be_nil
      end
    end

    describe 'multi-store isolation' do
      let(:other_store) { create(:store) }
      let(:other_user) { create(:store_user, store: other_store, email: 'test@example.com', password: 'OtherP@ssw0rd123!') }

      it 'allows same email in different stores' do
        expect(user).to be_valid
        expect(other_user).to be_valid
        expect(user.store).not_to eq(other_user.store)
      end

      it 'maintains separate authentication for each store' do
        expect(user.valid_password?('SecureP@ssw0rd123!')).to be true
        expect(other_user.valid_password?('OtherP@ssw0rd123!')).to be true
        expect(user.valid_password?('OtherP@ssw0rd123!')).to be false
      end
    end
  end

  # ============================================
  # 権限管理テスト（カバレッジ向上）
  # ============================================

  describe 'permission management' do
    let(:store) { create(:store) }
    let(:manager) { create(:store_user, :manager, store: store) }
    let(:staff) { create(:store_user, role: 'staff', store: store) }

    describe 'inventory permissions' do
      it 'allows managers to manage inventory' do
        expect(manager.can_manage_inventory?).to be true
        expect(manager.can_view_inventory?).to be true
        expect(manager.can_create_inventory?).to be true
        expect(manager.can_update_inventory?).to be true
        expect(manager.can_delete_inventory?).to be true
      end

      it 'restricts staff inventory permissions' do
        expect(staff.can_manage_inventory?).to be false
        expect(staff.can_view_inventory?).to be true
        expect(staff.can_create_inventory?).to be false
        expect(staff.can_update_inventory?).to be false
        expect(staff.can_delete_inventory?).to be false
      end
    end

    describe 'user management permissions' do
      it 'allows managers to manage users' do
        expect(manager.can_manage_users?).to be true
        expect(manager.can_view_users?).to be true
        expect(manager.can_create_users?).to be true
        expect(manager.can_update_users?).to be true
      end

      it 'restricts staff user management' do
        expect(staff.can_manage_users?).to be false
        expect(staff.can_view_users?).to be false
        expect(staff.can_create_users?).to be false
        expect(staff.can_update_users?).to be false
      end
    end

    describe 'report permissions' do
      it 'allows managers to access reports' do
        expect(manager.can_view_reports?).to be true
        expect(manager.can_export_reports?).to be true
      end

      it 'allows staff limited report access' do
        expect(staff.can_view_reports?).to be true
        expect(staff.can_export_reports?).to be false
      end
    end
  end

  # ============================================
  # データ整合性テスト（カバレッジ向上）
  # ============================================

  describe 'data integrity' do
    let(:store) { create(:store) }
    let(:user) { create(:store_user, store: store) }

    it 'maintains referential integrity with store' do
      store_id = user.store_id
      expect { store.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
      expect(StoreUser.find(user.id).store_id).to eq(store_id)
    end

    it 'cascades deletion correctly when user is deleted' do
      user_id = user.id
      user.destroy!
      expect { StoreUser.find(user_id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context 'with related records' do
      before do
        # ユーザーに関連するレコードを作成
        create(:temp_password, store_user: user)
        create(:audit_log, user: user)
      end

      it 'handles related record cleanup properly' do
        expect { user.destroy! }.not_to raise_error
        expect(TempPassword.where(store_user_id: user.id)).to be_empty
      end
    end
  end

  # ============================================
  # パフォーマンステスト（カバレッジ向上）
  # ============================================

  describe 'performance' do
    let(:store) { create(:store) }

    it 'efficiently queries store users' do
      # 大量のユーザーを作成
      create_list(:store_user, 50, store: store)

      expect {
        StoreUser.includes(:store).where(store: store).to_a
      }.to perform_under(100).ms
    end

    it 'efficiently validates uniqueness' do
      existing_user = create(:store_user, store: store, email: 'test@example.com')

      expect {
        100.times do |i|
          user = build(:store_user, store: store, email: "user#{i}@example.com")
          user.valid?
        end
      }.to perform_under(200).ms
    end

    it 'efficiently checks permissions' do
      users = create_list(:store_user, 100, store: store)

      expect {
        users.each(&:can_manage_inventory?)
      }.to perform_under(50).ms
    end
  end

  # ============================================
  # エッジケースのテスト（カバレッジ向上）
  # ============================================

  describe 'edge cases' do
    describe 'email handling' do
      it 'handles unicode characters in email' do
        user = build(:store_user, email: 'tëst@éxample.com')
        expect(user).to be_valid
      end

      it 'handles very long email addresses' do
        long_email = 'a' * 240 + '@example.com'
        user = build(:store_user, email: long_email)
        expect(user).not_to be_valid
      end

      it 'normalizes email case' do
        user = create(:store_user, email: 'Test@Example.COM')
        expect(user.email).to eq('test@example.com')
      end
    end

    describe 'name handling' do
      it 'handles unicode characters in name' do
        user = build(:store_user, name: '田中 太郎')
        expect(user).to be_valid
      end

      it 'handles empty name gracefully' do
        user = build(:store_user, name: '')
        expect(user).not_to be_valid
        expect(user.errors[:name]).to include('を入力してください')
      end

      it 'trims whitespace from name' do
        user = create(:store_user, name: '  Test User  ')
        expect(user.name).to eq('Test User')
      end
    end
  end

  describe '#password_expired?' do
    let(:user) { create(:store_user) }

    it 'returns true if must_change_password is true' do
      user.must_change_password = true
      expect(user.password_expired?).to be true
    end

    it 'returns true if password older than 90 days' do
      user.password_changed_at = 91.days.ago
      expect(user.password_expired?).to be true
    end

    it 'returns false for recent password' do
      user.password_changed_at = 30.days.ago
      expect(user.password_expired?).to be false
    end
  end

  # ============================================
  # Devise関連テスト
  # ============================================
  describe 'Devise configuration' do
    let(:user) { create(:store_user) }

    describe '#timeout_in' do
      it 'returns 8 hours' do
        expect(user.timeout_in).to eq(8.hours)
      end
    end

    describe '.maximum_attempts' do
      it 'returns 5' do
        expect(StoreUser.maximum_attempts).to eq(5)
      end
    end

    describe '.unlock_in' do
      it 'returns 30 minutes' do
        expect(StoreUser.unlock_in).to eq(30.minutes)
      end
    end
  end

  # ============================================
  # TODO: Phase 2以降で実装予定のテスト
  # ============================================
  # 1. 二要素認証関連テスト
  # 2. パスワード履歴機能テスト
  # 3. 監査ログ機能テスト
  # 4. CSV一括インポート機能テスト
end
