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
        expect(StoreUser.managers).to eq([manager])
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
    
    describe '#password_expired?' do
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
