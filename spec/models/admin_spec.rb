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

  # TODO: 将来実装予定の機能テスト
  # 1. Userモデルとの連携（ユーザーの作成・管理権限）
  # 2. 2要素認証（devise-two-factor）
  # 3. 権限レベル（admin/super_admin）による機能制限
end
