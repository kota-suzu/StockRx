# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailAuthService do
  let(:service) { described_class.new }
  let(:store_user) { create(:store_user) }
  let(:admin) { create(:admin) }
  let(:request_metadata) do
    {
      ip_address: "192.168.1.100",
      user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    }
  end

  # ============================================
  # 基本的なサービス検証
  # ============================================

  describe "configuration" do
    it "has default configuration values" do
      expect(service.config.max_attempts_per_hour).to eq(3)
      expect(service.config.max_attempts_per_day).to eq(10)
      expect(service.config.temp_password_expiry).to eq(15.minutes)
      expect(service.config.rate_limit_enabled).to be true
      expect(service.config.email_delivery_timeout).to eq(30.seconds)
      expect(service.config.security_monitoring_enabled).to be true
    end
  end

  describe "error classes" do
    it "defines proper error hierarchy" do
      expect(EmailAuthService::EmailAuthError).to be < StandardError
      expect(EmailAuthService::TempPasswordGenerationError).to be < EmailAuthService::EmailAuthError
      expect(EmailAuthService::EmailDeliveryError).to be < EmailAuthService::EmailAuthError
      expect(EmailAuthService::SecurityViolationError).to be < EmailAuthService::EmailAuthError
      expect(EmailAuthService::RateLimitExceededError).to be < EmailAuthService::SecurityViolationError
      expect(EmailAuthService::UserIneligibleError).to be < EmailAuthService::SecurityViolationError
    end
  end

  # ============================================
  # 一時パスワード生成・送信機能
  # ============================================

  describe "#generate_and_send_temp_password" do
    context "when successful" do
      let(:temp_password) { create(:temp_password, store_user: store_user) }
      let(:plain_password) { "12345678" }

      before do
        allow(TempPassword).to receive(:generate_for_user)
          .and_return([ temp_password, plain_password ])
        allow(service).to receive(:validate_rate_limit)
        allow(service).to receive(:validate_user_eligibility)
        allow(service).to receive(:deliver_temp_password_email)
          .and_return({ success: true, delivered_at: Time.current })
      end

      it "generates temp password and sends email successfully" do
        result = service.generate_and_send_temp_password(
          store_user,
          admin_id: admin.id,
          request_metadata: request_metadata
        )

        expect(result[:success]).to be true
        expect(result[:temp_password_id]).to eq(temp_password.id)
        expect(result[:expires_at]).to eq(temp_password.expires_at)
        expect(result[:delivery_result]).to include(success: true)
      end

      it "calls all required validation methods" do
        expect(service).to receive(:validate_rate_limit)
          .with(store_user.email, request_metadata[:ip_address])
        expect(service).to receive(:validate_user_eligibility)
          .with(store_user)

        service.generate_and_send_temp_password(
          store_user,
          admin_id: admin.id,
          request_metadata: request_metadata
        )
      end

      it "logs security event for successful generation" do
        expect(Rails.logger).to receive(:info).at_least(:once)

        service.generate_and_send_temp_password(
          store_user,
          admin_id: admin.id,
          request_metadata: request_metadata
        )
      end
    end

    context "when rate limited" do
      before do
        allow(service).to receive(:validate_rate_limit)
          .and_raise(EmailAuthService::RateLimitExceededError, "Rate limit exceeded")
      end

      it "raises rate limit error" do
        expect {
          service.generate_and_send_temp_password(store_user, request_metadata: request_metadata)
        }.to raise_error(EmailAuthService::RateLimitExceededError, "Rate limit exceeded")
      end
    end

    context "when user is ineligible" do
      let(:inactive_user) { create(:store_user, :inactive) }

      it "raises UserIneligibleError for inactive user" do
        expect {
          service.generate_and_send_temp_password(
            inactive_user,
            request_metadata: request_metadata
          )
        }.to raise_error(EmailAuthService::UserIneligibleError, "User account is not active")
      end
    end

    context "when temp password generation fails" do
      before do
        allow(service).to receive(:validate_rate_limit)
        allow(service).to receive(:validate_user_eligibility)
        allow(TempPassword).to receive(:generate_for_user)
          .and_raise(ActiveRecord::RecordInvalid, "Validation failed")
      end

      it "handles generation error gracefully" do
        result = service.generate_and_send_temp_password(
          store_user,
          request_metadata: request_metadata
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('temp_password_generation_failed')
        expect(result[:details]).to include("Failed to generate temp password")
      end
    end
  end

  # ============================================
  # 一時パスワード認証機能
  # ============================================

  describe "#authenticate_with_temp_password" do
    context "when successful authentication" do
      let(:plain_password) { "12345678" }
      let(:temp_password) { create(:temp_password, :with_plain_password, store_user: store_user, plain_password: plain_password) }

      before do
        allow(service).to receive(:find_valid_temp_password)
          .and_return(temp_password)
        allow(service).to receive(:validate_authentication_rate_limit)
      end

      it "authenticates successfully with correct password" do
        result = service.authenticate_with_temp_password(
          store_user,
          plain_password,
          request_metadata: request_metadata
        )

        expect(result[:success]).to be true
        expect(result[:temp_password_id]).to eq(temp_password.id)
        expect(result[:authenticated_at]).to be_present
      end

      it "marks temp password as used" do
        expect(temp_password).to receive(:mark_as_used!)
          .with(
            ip_address: request_metadata[:ip_address],
            user_agent: request_metadata[:user_agent]
          )

        service.authenticate_with_temp_password(
          store_user,
          plain_password,
          request_metadata: request_metadata
        )
      end

      it "logs successful authentication" do
        expect(Rails.logger).to receive(:info).at_least(:once)

        service.authenticate_with_temp_password(
          store_user,
          plain_password,
          request_metadata: request_metadata
        )
      end
    end

    context "when authentication fails" do
      let(:plain_password) { "12345678" }
      let(:wrong_password) { "wrongpass" }
      let(:temp_password) { create(:temp_password, :with_plain_password, store_user: store_user, plain_password: plain_password) }

      before do
        allow(service).to receive(:find_valid_temp_password)
          .and_return(temp_password)
        allow(service).to receive(:validate_authentication_rate_limit)
      end

      it "fails with incorrect password" do
        result = service.authenticate_with_temp_password(
          store_user,
          wrong_password,
          request_metadata: request_metadata
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('authentication_failed')
        expect(result[:reason]).to eq('invalid_password')
      end

      it "increments usage attempts on failure" do
        expect(temp_password).to receive(:increment_usage_attempts!)
          .with(ip_address: request_metadata[:ip_address])

        service.authenticate_with_temp_password(
          store_user,
          wrong_password,
          request_metadata: request_metadata
        )
      end

      it "logs failed authentication" do
        expect(Rails.logger).to receive(:info).at_least(:once)

        service.authenticate_with_temp_password(
          store_user,
          wrong_password,
          request_metadata: request_metadata
        )
      end
    end

    context "when no valid temp password exists" do
      before do
        allow(service).to receive(:find_valid_temp_password)
          .and_return(nil)
        allow(service).to receive(:validate_authentication_rate_limit)
      end

      it "returns appropriate error" do
        result = service.authenticate_with_temp_password(
          store_user,
          "anypassword",
          request_metadata: request_metadata
        )

        expect(result[:success]).to be false
        expect(result[:reason]).to eq('no_valid_temp_password')
      end
    end
  end

  # ============================================
  # クリーンアップ機能
  # ============================================

  describe "#cleanup_expired_passwords" do
    it "calls TempPassword.cleanup_expired and logs the result" do
      expect(TempPassword).to receive(:cleanup_expired).and_return(5)
      expect(Rails.logger).to receive(:info).at_least(:once)

      result = service.cleanup_expired_passwords

      expect(result).to eq(5)
    end
  end

  # ============================================
  # プライベートメソッドテスト（重要な機能のみ）
  # ============================================

  describe "private methods" do
    describe "#validate_rate_limit" do
      context "when rate limiting is enabled" do
        before { service.config.rate_limit_enabled = true }

        it "allows requests within limits" do
          expect {
            service.send(:validate_rate_limit, store_user.email, request_metadata[:ip_address])
          }.not_to raise_error
        end

        context "when hourly limit exceeded" do
          before do
            allow(service).to receive(:redis_increment_with_expiry)
              .and_return(service.config.max_attempts_per_hour + 1)
          end

          it "raises rate limit error" do
            expect {
              service.send(:validate_rate_limit, store_user.email, request_metadata[:ip_address])
            }.to raise_error(EmailAuthService::RateLimitExceededError, /Hourly rate limit exceeded/)
          end
        end
      end

      context "when rate limiting is disabled" do
        before { service.config.rate_limit_enabled = false }

        it "skips rate limit validation" do
          expect(service).not_to receive(:redis_increment_with_expiry)

          expect {
            service.send(:validate_rate_limit, store_user.email, request_metadata[:ip_address])
          }.not_to raise_error
        end
      end
    end

    describe "#validate_user_eligibility" do
      context "with active user" do
        it "passes validation" do
          expect {
            service.send(:validate_user_eligibility, store_user)
          }.not_to raise_error
        end
      end

      context "with inactive user" do
        let(:inactive_user) { create(:store_user, :inactive) }

        it "raises UserIneligibleError" do
          expect {
            service.send(:validate_user_eligibility, inactive_user)
          }.to raise_error(EmailAuthService::UserIneligibleError, "User account is not active")
        end
      end

      context "with locked user" do
        let(:locked_user) { create(:store_user, :locked) }

        it "raises UserIneligibleError" do
          expect {
            service.send(:validate_user_eligibility, locked_user)
          }.to raise_error(EmailAuthService::UserIneligibleError, "User account is locked")
        end
      end
    end

    describe "#find_valid_temp_password" do
      let!(:expired_password) { create(:temp_password, :expired, store_user: store_user) }
      let!(:used_password) { create(:temp_password, :used, store_user: store_user) }
      let!(:valid_password) { create(:temp_password, store_user: store_user) }

      it "returns the most recent valid temp password" do
        result = service.send(:find_valid_temp_password, store_user)

        expect(result).to eq(valid_password)
      end

      it "excludes expired and used passwords" do
        result = service.send(:find_valid_temp_password, store_user)

        expect(result).not_to eq(expired_password)
        expect(result).not_to eq(used_password)
      end
    end
  end

  # ============================================
  # 設定・カスタマイズテスト
  # ============================================

  describe "configuration customization" do
    it "allows configuration override" do
      service.config.max_attempts_per_hour = 5
      service.config.rate_limit_enabled = false

      expect(service.config.max_attempts_per_hour).to eq(5)
      expect(service.config.rate_limit_enabled).to be false
    end
  end

  # ============================================
  # セキュリティ機能テスト（重要な新機能）
  # ============================================

  describe "rate limiting functionality" do
    let(:email) { store_user.email }
    let(:ip_address) { '192.168.1.100' }

    describe "#rate_limit_check" do
      context "when rate limiting is enabled" do
        before { service.config.rate_limit_enabled = true }

        it "returns true when no previous attempts" do
          result = service.rate_limit_check(email, ip_address)
          expect(result).to be true
        end

        it "returns false when hourly limit exceeded" do
          # 時間別制限を超過させる
          allow(service).to receive(:get_rate_limit_count).and_return(5)

          result = service.rate_limit_check(email, ip_address)
          expect(result).to be false
        end

        it "checks all three rate limit types (hourly, daily, IP)" do
          expect(service).to receive(:get_rate_limit_count).exactly(3).times.and_return(0)
          service.rate_limit_check(email, ip_address)
        end
      end

      context "when rate limiting is disabled" do
        before { service.config.rate_limit_enabled = false }

        it "always returns true" do
          result = service.rate_limit_check(email, ip_address)
          expect(result).to be true
        end

        it "does not check rate limit counts" do
          expect(service).not_to receive(:get_rate_limit_count)
          service.rate_limit_check(email, ip_address)
        end
      end
    end

    describe "#record_authentication_attempt" do
      context "when rate limiting is enabled" do
        before { service.config.rate_limit_enabled = true }

        it "increments rate limit counter successfully" do
          expect(service).to receive(:increment_rate_limit_counter).with(email, ip_address)

          result = service.record_authentication_attempt(email, ip_address)
          expect(result).to be true
        end

        it "logs security event on successful recording" do
          allow(service).to receive(:increment_rate_limit_counter)
          expect(service).to receive(:log_security_event).with(
            'authentication_attempt_recorded',
            nil,
            hash_including(email: email, ip_address: ip_address)
          )

          service.record_authentication_attempt(email, ip_address)
        end

        it "handles errors gracefully and returns false" do
          allow(service).to receive(:increment_rate_limit_counter).and_raise(StandardError, 'Redis error')

          result = service.record_authentication_attempt(email, ip_address)
          expect(result).to be false
        end

        it "logs error when increment fails" do
          allow(service).to receive(:increment_rate_limit_counter).and_raise(StandardError, 'Redis error')
          expect(Rails.logger).to receive(:error).with(/Failed to record authentication attempt/)

          service.record_authentication_attempt(email, ip_address)
        end
      end

      context "when rate limiting is disabled" do
        before { service.config.rate_limit_enabled = false }

        it "returns immediately without processing" do
          expect(service).not_to receive(:increment_rate_limit_counter)

          result = service.record_authentication_attempt(email, ip_address)
          expect(result).to be_nil
        end
      end
    end

    describe "#increment_rate_limit_counter" do
      let(:email) { store_user.email }
      let(:ip_address) { '192.168.1.100' }

      context "when rate limiting is enabled" do
        before { service.config.rate_limit_enabled = true }

        it "increments all three counter types" do
          expect(service).to receive(:redis_increment_with_expiry).exactly(3).times

          service.send(:increment_rate_limit_counter, email, ip_address)
        end

        it "uses correct key patterns" do
          expect(service).to receive(:redis_increment_with_expiry).with(
            /email_auth_service:hourly:#{email}/, 1.hour
          )
          expect(service).to receive(:redis_increment_with_expiry).with(
            /email_auth_service:daily:#{email}/, 1.day
          )
          expect(service).to receive(:redis_increment_with_expiry).with(
            /email_auth_service:rate_limit:#{email}:#{ip_address}/, 1.hour
          )

          service.send(:increment_rate_limit_counter, email, ip_address)
        end
      end

      context "when rate limiting is disabled" do
        before { service.config.rate_limit_enabled = false }

        it "returns immediately without processing" do
          expect(service).not_to receive(:redis_increment_with_expiry)

          service.send(:increment_rate_limit_counter, email, ip_address)
        end
      end
    end

    describe "Redis integration (memory-based implementation)" do
      describe "#redis_increment_with_expiry" do
        let(:test_key) { 'test_key' }
        let(:expiry_time) { 1.hour }

        it "initializes counter for new key" do
          result = service.send(:redis_increment_with_expiry, test_key, expiry_time)
          expect(result).to eq(1)
        end

        it "increments existing counter" do
          service.send(:redis_increment_with_expiry, test_key, expiry_time)
          result = service.send(:redis_increment_with_expiry, test_key, expiry_time)
          expect(result).to eq(2)
        end

        it "resets expired counter" do
          # 初回設定
          service.send(:redis_increment_with_expiry, test_key, 0.seconds)

          # 時間を進める（期限切れをシミュレート）
          allow(Time).to receive(:current).and_return(Time.current + 1.hour)

          result = service.send(:redis_increment_with_expiry, test_key, expiry_time)
          expect(result).to eq(1)
        end
      end

      describe "#get_rate_limit_count" do
        let(:test_key) { 'test_key' }

        it "returns 0 for non-existent key" do
          result = service.send(:get_rate_limit_count, test_key)
          expect(result).to eq(0)
        end

        it "returns current count for existing key" do
          service.send(:redis_increment_with_expiry, test_key, 1.hour)
          service.send(:redis_increment_with_expiry, test_key, 1.hour)

          result = service.send(:get_rate_limit_count, test_key)
          expect(result).to eq(2)
        end

        it "returns 0 for expired key" do
          service.send(:redis_increment_with_expiry, test_key, 0.seconds)

          # 時間を進める
          allow(Time).to receive(:current).and_return(Time.current + 1.hour)

          result = service.send(:get_rate_limit_count, test_key)
          expect(result).to eq(0)
        end
      end
    end

    describe "audit logging" do
      let(:test_metadata) { { test_key: 'test_value', ip_address: '192.168.1.100' } }

      context "when security monitoring is enabled" do
        before { service.config.security_monitoring_enabled = true }

        it "logs structured security event" do
          expect(Rails.logger).to receive(:info) do |log_data|
            parsed_data = JSON.parse(log_data)
            expect(parsed_data['event']).to eq('email_auth_test_event')
            expect(parsed_data['service']).to eq('EmailAuthService')
            expect(parsed_data['user_id']).to eq(store_user.id)
            expect(parsed_data['user_email']).to eq(store_user.email)
            expect(parsed_data['test_key']).to eq('test_value')
          end

          service.send(:log_security_event, 'test_event', store_user, test_metadata)
        end

        it "handles logging errors gracefully" do
          allow(Rails.logger).to receive(:info).and_raise(StandardError, 'Logging error')
          expect(Rails.logger).to receive(:error).with(/Security logging failed/)

          expect {
            service.send(:log_security_event, 'test_event', store_user, test_metadata)
          }.not_to raise_error
        end
      end

      context "when security monitoring is disabled" do
        before { service.config.security_monitoring_enabled = false }

        it "does not log events" do
          expect(Rails.logger).not_to receive(:info)
          service.send(:log_security_event, 'test_event', store_user, test_metadata)
        end
      end
    end

    describe "timing attack protection" do
      # TODO: 🟢 Phase 3推奨 - タイミング攻撃対策テスト
      it "TODO: implements timing attack protection verification"
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance" do
    # TODO: 🟡 Phase 2重要 - パフォーマンステスト実装
    it "TODO: implements performance benchmarks for high-load scenarios"
  end

  # ============================================
  # 統合テスト（実際のユースケース）
  # ============================================

  describe "integration scenarios" do
    describe "complete email authentication flow" do
      let(:plain_password) { "12345678" }

      it "handles full authentication lifecycle" do
        # Step 1: Generate and send temp password
        generation_result = service.generate_and_send_temp_password(
          store_user,
          admin_id: admin.id,
          request_metadata: request_metadata
        )

        expect(generation_result[:success]).to be true

        # Step 2: Find the generated temp password
        temp_password = TempPassword.find(generation_result[:temp_password_id])
        generated_password = TempPassword.generate_secure_password

        # Simulate password delivery (since we can't get the actual password from service)
        temp_password.plain_password = generated_password
        temp_password.encrypt_password_if_changed
        temp_password.save!

        # Step 3: Authenticate with temp password
        auth_result = service.authenticate_with_temp_password(
          store_user,
          generated_password,
          request_metadata: request_metadata
        )

        expect(auth_result[:success]).to be true
        expect(temp_password.reload).to be_used
      end
    end

    describe "security violation handling" do
      it "handles multiple failed attempts gracefully" do
        temp_password = create(:temp_password, :with_plain_password,
                              store_user: store_user, plain_password: "correct")

        # Multiple failed attempts
        5.times do |i|
          result = service.authenticate_with_temp_password(
            store_user,
            "wrong_password_#{i}",
            request_metadata: request_metadata
          )

          expect(result[:success]).to be false
        end

        # Verify temp password is locked
        expect(temp_password.reload).to be_locked
      end
    end
  end
end
