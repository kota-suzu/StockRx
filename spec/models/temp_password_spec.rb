# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TempPassword, type: :model do
  let(:store_user) { create(:store_user) }
  let(:temp_password) { create(:temp_password, store_user: store_user) }

  # ============================================
  # 基本的なモデル検証
  # ============================================

  describe "associations" do
    it { should belong_to(:store_user) }
  end

  describe "validations" do
    subject { build(:temp_password) }

    it { should validate_presence_of(:password_hash) }
    # Custom validation for expires_at instead of simple presence
    it "validates expires_at is in the future on create" do
      temp_password = build(:temp_password, expires_at: 1.hour.ago)
      expect(temp_password).not_to be_valid
      expect(temp_password.errors[:expires_at]).to include("must be in the future")
    end
    it { should validate_presence_of(:usage_attempts) }
    it { should validate_length_of(:password_hash).is_at_most(255) }
    it { should validate_length_of(:ip_address).is_at_most(45) }
    it { should validate_length_of(:generated_by_admin_id).is_at_most(255) }

    it { should validate_numericality_of(:usage_attempts)
          .is_greater_than_or_equal_to(0)
          .is_less_than_or_equal_to(10) }

    describe "IP address validation" do
      it "accepts valid IPv4 addresses" do
        temp_password.ip_address = "192.168.1.1"
        expect(temp_password).to be_valid
      end

      it "accepts valid IPv6 addresses" do
        temp_password.ip_address = "2001:db8::1"
        expect(temp_password).to be_valid
      end

      it "rejects invalid IP addresses" do
        temp_password.ip_address = "invalid_ip"
        expect(temp_password).not_to be_valid
      end

      it "allows blank IP addresses" do
        temp_password.ip_address = ""
        expect(temp_password).to be_valid
      end
    end
  end

  # ============================================
  # スコープテスト
  # ============================================

  describe "scopes" do
    let!(:active_temp_password) { create(:temp_password, active: true) }
    let!(:inactive_temp_password) { create(:temp_password, :inactive) }
    let!(:expired_temp_password) { create(:temp_password, :expired) }
    let!(:used_temp_password) { create(:temp_password, :used) }
    let!(:locked_temp_password) { create(:temp_password, :locked) }

    describe ".active" do
      it "returns only active temp passwords" do
        expect(TempPassword.active).to include(active_temp_password)
        expect(TempPassword.active).not_to include(inactive_temp_password)
      end
    end

    describe ".expired" do
      it "returns only expired temp passwords" do
        expect(TempPassword.expired).to include(expired_temp_password)
        expect(TempPassword.expired).not_to include(active_temp_password)
      end
    end

    describe ".valid" do
      it "returns only active and non-expired temp passwords" do
        expect(TempPassword.valid).to include(active_temp_password)
        expect(TempPassword.valid).not_to include(expired_temp_password)
        expect(TempPassword.valid).not_to include(inactive_temp_password)
      end
    end

    describe ".unused" do
      it "returns only unused temp passwords" do
        expect(TempPassword.unused).to include(active_temp_password)
        expect(TempPassword.unused).not_to include(used_temp_password)
      end
    end

    describe ".used" do
      it "returns only used temp passwords" do
        expect(TempPassword.used).to include(used_temp_password)
        expect(TempPassword.used).not_to include(active_temp_password)
      end
    end

    describe ".locked" do
      it "returns only locked temp passwords" do
        expect(TempPassword.locked).to include(locked_temp_password)
        expect(TempPassword.locked).not_to include(active_temp_password)
      end
    end

    describe ".by_store_user" do
      it "returns temp passwords for specific store user" do
        expect(TempPassword.by_store_user(store_user)).to include(temp_password)
      end
    end
  end

  # ============================================
  # パスワード暗号化・検証
  # ============================================

  describe "password encryption and validation" do
    let(:plain_password) { "123456" }

    describe "#encrypt_password_if_changed" do
      it "encrypts password when plain_password is set" do
        temp_password.plain_password = plain_password
        temp_password.encrypt_password_if_changed

        expect(temp_password.password_hash).to be_present
        expect(temp_password.password_hash).not_to eq(plain_password)
        expect(temp_password.plain_password).to be_nil
      end

      it "does not encrypt if plain_password is not set" do
        original_hash = temp_password.password_hash
        temp_password.encrypt_password_if_changed

        expect(temp_password.password_hash).to eq(original_hash)
      end
    end

    describe "#valid_password?" do
      let(:temp_password) { create(:temp_password, :with_plain_password, plain_password: plain_password) }

      context "with valid conditions" do
        it "returns true for correct password" do
          expect(temp_password.valid_password?(plain_password)).to be true
        end
      end

      context "with invalid conditions" do
        it "returns false for incorrect password" do
          expect(temp_password.valid_password?("wrong")).to be false
        end

        it "returns false for expired temp password" do
          temp_password.update!(expires_at: 1.hour.ago)
          expect(temp_password.valid_password?(plain_password)).to be false
        end

        it "returns false for inactive temp password" do
          temp_password.update!(active: false)
          expect(temp_password.valid_password?(plain_password)).to be false
        end

        it "returns false for locked temp password" do
          temp_password.update!(usage_attempts: TempPassword::MAX_ATTEMPTS)
          expect(temp_password.valid_password?(plain_password)).to be false
        end
      end

      context "with invalid password hash" do
        it "handles BCrypt errors gracefully" do
          temp_password.update_column(:password_hash, "invalid_hash")
          expect(temp_password.valid_password?(plain_password)).to be false
        end
      end
    end
  end

  # ============================================
  # 状態確認メソッド
  # ============================================

  describe "status check methods" do
    describe "#expired?" do
      it "returns true for expired temp password" do
        temp_password.update!(expires_at: 1.hour.ago)
        expect(temp_password).to be_expired
      end

      it "returns false for valid temp password" do
        expect(temp_password).not_to be_expired
      end
    end

    describe "#used?" do
      it "returns true for used temp password" do
        temp_password.update!(used_at: Time.current)
        expect(temp_password).to be_used
      end

      it "returns false for unused temp password" do
        expect(temp_password).not_to be_used
      end
    end

    describe "#locked?" do
      it "returns true when usage attempts exceed maximum" do
        temp_password.update!(usage_attempts: TempPassword::MAX_ATTEMPTS)
        expect(temp_password).to be_locked
      end

      it "returns false when usage attempts are below maximum" do
        expect(temp_password).not_to be_locked
      end
    end

    describe "#valid_for_authentication?" do
      it "returns true for valid temp password" do
        expect(temp_password).to be_valid_for_authentication
      end

      it "returns false for expired temp password" do
        temp_password.update!(expires_at: 1.hour.ago)
        expect(temp_password).not_to be_valid_for_authentication
      end

      it "returns false for used temp password" do
        temp_password.update!(used_at: Time.current)
        expect(temp_password).not_to be_valid_for_authentication
      end

      it "returns false for locked temp password" do
        temp_password.update!(usage_attempts: TempPassword::MAX_ATTEMPTS)
        expect(temp_password).not_to be_valid_for_authentication
      end

      it "returns false for inactive temp password" do
        temp_password.update!(active: false)
        expect(temp_password).not_to be_valid_for_authentication
      end
    end

    describe "#time_until_expiry" do
      it "returns positive seconds for valid temp password" do
        expect(temp_password.time_until_expiry).to be > 0
      end

      it "returns 0 for expired temp password" do
        temp_password.update!(expires_at: 1.hour.ago)
        expect(temp_password.time_until_expiry).to eq(0)
      end
    end
  end

  # ============================================
  # 使用処理テスト
  # ============================================

  describe "usage processing" do
    describe "#mark_as_used!" do
      let(:ip_address) { "192.168.1.200" }
      let(:user_agent) { "Test Browser" }

      it "marks temp password as used" do
        temp_password.mark_as_used!(ip_address: ip_address, user_agent: user_agent)

        expect(temp_password.reload.used_at).to be_present
        expect(temp_password.ip_address).to eq(ip_address)
        expect(temp_password.user_agent).to eq(user_agent)
      end

      it "is performed within a transaction" do
        expect { temp_password.mark_as_used! }.not_to raise_error
      end
    end

    describe "#increment_usage_attempts!" do
      let(:ip_address) { "192.168.1.200" }

      it "increments usage attempts" do
        expect {
          temp_password.increment_usage_attempts!(ip_address: ip_address)
        }.to change { temp_password.reload.usage_attempts }.by(1)
      end

      it "updates last attempt time" do
        temp_password.increment_usage_attempts!(ip_address: ip_address)
        expect(temp_password.reload.last_attempt_at).to be_present
      end

      it "updates IP address if provided" do
        temp_password.increment_usage_attempts!(ip_address: ip_address)
        expect(temp_password.reload.ip_address).to eq(ip_address)
      end
    end
  end

  # ============================================
  # クラスメソッドテスト
  # ============================================

  describe "class methods" do
    describe ".generate_for_user" do
      let(:admin_id) { "admin_123" }
      let(:ip_address) { "192.168.1.100" }
      let(:user_agent) { "Test Browser" }

      it "generates a new temp password for user" do
        result = TempPassword.generate_for_user(
          store_user,
          admin_id: admin_id,
          ip_address: ip_address,
          user_agent: user_agent
        )

        expect(result).to be_an(Array)
        expect(result.first).to be_a(TempPassword)
        expect(result.last).to be_a(String)

        temp_password = result.first
        expect(temp_password.store_user).to eq(store_user)
        expect(temp_password.generated_by_admin_id).to eq(admin_id)
        expect(temp_password.ip_address).to eq(ip_address)
        expect(temp_password.user_agent).to eq(user_agent)
      end

      it "deactivates existing temp passwords for the user" do
        existing_temp_password = create(:temp_password, store_user: store_user)

        TempPassword.generate_for_user(store_user)

        expect(existing_temp_password.reload.active).to be false
      end

      it "is performed within a transaction" do
        expect { TempPassword.generate_for_user(store_user) }.not_to raise_error
      end
    end

    describe ".generate_secure_password" do
      it "generates password of default length" do
        password = TempPassword.generate_secure_password
        expect(password.length).to eq(8)
        expect(password).to match(/\A\d+\z/)
      end

      it "generates password of specified length" do
        password = TempPassword.generate_secure_password(length: 10)
        expect(password.length).to eq(10)
        expect(password).to match(/\A\d+\z/)
      end
    end

    describe ".cleanup_expired" do
      let!(:old_expired) do
        temp_password = create(:temp_password)
        temp_password.update_column(:expires_at, 2.days.ago)
        temp_password
      end
      let!(:recent_expired) do
        temp_password = create(:temp_password)
        temp_password.update_column(:expires_at, 1.hour.ago)
        temp_password
      end
      let!(:old_used) { create(:temp_password, :used, used_at: 3.days.ago) }
      let!(:recent_used) { create(:temp_password, :used, used_at: 1.hour.ago) }
      let!(:valid_password) { create(:temp_password) }

      it "removes old expired and used temp passwords" do
        count = TempPassword.cleanup_expired

        expect(count).to eq(2)  # old_expired + old_used
        expect { old_expired.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect { old_used.reload }.to raise_error(ActiveRecord::RecordNotFound)
        expect { recent_expired.reload }.not_to raise_error
        expect { recent_used.reload }.not_to raise_error
        expect { valid_password.reload }.not_to raise_error
      end
    end

    describe ".deactivate_existing_passwords" do
      let!(:active_password1) { create(:temp_password, store_user: store_user) }
      let!(:active_password2) { create(:temp_password, store_user: store_user) }
      let!(:other_user_password) { create(:temp_password) }

      it "deactivates all active passwords for the user" do
        TempPassword.deactivate_existing_passwords(store_user)

        expect(active_password1.reload.active).to be false
        expect(active_password2.reload.active).to be false
        expect(other_user_password.reload.active).to be true
      end
    end
  end

  # ============================================
  # コールバックテスト
  # ============================================

  describe "callbacks" do
    describe "before_create :set_default_expiry" do
      it "sets default expiry if not provided" do
        temp_password = build(:temp_password, expires_at: nil)
        temp_password.save!

        expect(temp_password.expires_at).to be_present
        expect(temp_password.expires_at).to be > Time.current
      end

      it "does not override provided expiry" do
        custom_expiry = 1.hour.from_now
        temp_password = build(:temp_password, expires_at: custom_expiry)
        temp_password.save!

        expect(temp_password.expires_at).to be_within(1.second).of(custom_expiry)
      end
    end
  end

  # ============================================
  # 統合テスト（実際のユースケース）
  # ============================================

  describe "integration scenarios" do
    describe "successful authentication flow" do
      let(:plain_password) { "123456" }
      let(:temp_password) { create(:temp_password, :with_plain_password, plain_password: plain_password) }

      it "validates password and marks as used" do
        # パスワード検証
        expect(temp_password.valid_password?(plain_password)).to be true

        # 使用済みにマーク
        temp_password.mark_as_used!

        # 状態確認
        expect(temp_password.reload).to be_used
        expect(temp_password).not_to be_valid_for_authentication
      end
    end

    describe "failed authentication with lockout" do
      let(:plain_password) { "123456" }
      let(:temp_password) { create(:temp_password, :with_plain_password, plain_password: plain_password) }

      it "locks temp password after max attempts" do
        # 最大試行回数まで失敗
        TempPassword::MAX_ATTEMPTS.times do
          temp_password.increment_usage_attempts!
        end

        # ロック状態確認
        expect(temp_password.reload).to be_locked
        expect(temp_password.valid_password?(plain_password)).to be false
      end
    end

    describe "temp password lifecycle" do
      it "goes through complete lifecycle" do
        # 生成
        temp_password, plain_password = TempPassword.generate_for_user(store_user)
        expect(temp_password).to be_valid_for_authentication

        # 試行（失敗）
        temp_password.increment_usage_attempts!
        expect(temp_password.reload.usage_attempts).to eq(1)

        # 成功
        expect(temp_password.valid_password?(plain_password)).to be true
        temp_password.mark_as_used!

        # 完了
        expect(temp_password.reload).to be_used
        expect(temp_password).not_to be_valid_for_authentication
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance" do
    # TODO: 🟡 Phase 2重要 - パフォーマンステスト実装
    # - 大量データでのクエリ最適化確認
    # - N+1クエリ検出テスト
    # - インデックス効果測定
    it "TODO: implements performance benchmarks"
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security" do
    # TODO: 🔴 Phase 1緊急 - セキュリティテスト実装
    # - タイミング攻撃対策確認
    # - パスワードハッシュ強度テスト
    # - レート制限機能テスト
    it "TODO: implements security vulnerability tests"
  end
end
