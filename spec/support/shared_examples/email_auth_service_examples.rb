# frozen_string_literal: true

# ============================================================================
# EmailAuthService用共通テストパターン
# CLAUDE.md準拠: shared_examples活用による保守性向上とDRY原則実装
# ============================================================================

RSpec.shared_examples "rate limit validation behavior" do |method_name, error_type = EmailAuthService::RateLimitExceededError|
  let(:service) { described_class.new }
  let(:email) { "test@example.com" }
  let(:ip_address) { "192.168.1.100" }

  context "when rate limiting is enabled" do
    before { service.config.rate_limit_enabled = true }

    it "allows requests within rate limits" do
      allow(service).to receive(:redis_increment_with_expiry).and_return(1)

      expect {
        service.send(method_name, email, ip_address)
      }.not_to raise_error
    end

    it "raises #{error_type} when hourly limit exceeded" do
      allow(service).to receive(:redis_increment_with_expiry)
        .and_return(service.config.max_attempts_per_hour + 1)

      expect {
        service.send(method_name, email, ip_address)
      }.to raise_error(error_type, /rate limit exceeded/)
    end

    it "raises #{error_type} when daily limit exceeded" do
      allow(service).to receive(:redis_increment_with_expiry)
        .and_return(1, service.config.max_attempts_per_day + 1)

      expect {
        service.send(method_name, email, ip_address)
      }.to raise_error(error_type, /rate limit exceeded/)
    end

    it "raises #{error_type} when IP limit exceeded" do
      allow(service).to receive(:redis_increment_with_expiry)
        .and_return(1, 1, service.config.max_attempts_per_hour + 1)

      expect {
        service.send(method_name, email, ip_address)
      }.to raise_error(error_type, /rate limit exceeded/)
    end
  end

  context "when rate limiting is disabled" do
    before { service.config.rate_limit_enabled = false }

    it "bypasses rate limit checks" do
      expect(service).not_to receive(:redis_increment_with_expiry)

      expect {
        service.send(method_name, email, ip_address)
      }.not_to raise_error
    end
  end
end

RSpec.shared_examples "security logging behavior" do |event_name|
  let(:service) { described_class.new }
  let(:store_user) { build_stubbed(:store_user) }
  let(:metadata) { { test_key: "test_value", ip_address: "192.168.1.100" } }

  context "when security monitoring is enabled" do
    before { service.config.security_monitoring_enabled = true }

    it "logs structured security events" do
      expect(Rails.logger).to receive(:info) do |log_data|
        parsed_data = JSON.parse(log_data)
        expect(parsed_data['event']).to eq("email_auth_#{event_name}")
        expect(parsed_data['service']).to eq('EmailAuthService')
        expect(parsed_data['user_id']).to eq(store_user.id)
        expect(parsed_data['user_email']).to eq(store_user.email)
        expect(parsed_data['test_key']).to eq('test_value')
      end

      service.send(:log_security_event, event_name, store_user, metadata)
    end

    it "includes timestamp in ISO8601 format" do
      allow(Rails.logger).to receive(:info) do |log_data|
        parsed_data = JSON.parse(log_data)
        expect(parsed_data['timestamp']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      service.send(:log_security_event, event_name, store_user, metadata)
    end

    it "handles logging errors gracefully" do
      allow(Rails.logger).to receive(:info).and_raise(StandardError, "Log server down")
      expect(Rails.logger).to receive(:error).with(/Security logging failed/)

      expect {
        service.send(:log_security_event, event_name, store_user, metadata)
      }.not_to raise_error
    end
  end

  context "when security monitoring is disabled" do
    before { service.config.security_monitoring_enabled = false }

    it "skips logging" do
      expect(Rails.logger).not_to receive(:info)
      service.send(:log_security_event, event_name, store_user, metadata)
    end
  end
end

RSpec.shared_examples "error handler behavior" do |handler_method, error_class, expected_error_key|
  let(:service) { described_class.new }
  let(:store_user) { build_stubbed(:store_user) }
  let(:admin) { build_stubbed(:admin) }
  let(:request_metadata) do
    {
      ip_address: "192.168.1.100",
      user_agent: "Test Agent",
      referer: "https://example.com"
    }
  end

  it "returns proper error structure" do
    error = error_class.new("Test error message")

    result = service.send(
      handler_method,
      error,
      store_user,
      admin&.id,
      request_metadata
    )

    expect(result).to be_a(Hash)
    expect(result[:success]).to be false
    expect(result[:error]).to eq(expected_error_key)
    expect(result[:details]).to include("Test error message")
  end

  it "logs security event for error" do
    error = error_class.new("Test error message")
    expect(Rails.logger).to receive(:info).with(hash_including(
      event: /email_auth_/
    ))

    service.send(
      handler_method,
      error,
      store_user,
      admin&.id,
      request_metadata
    )
  end

  it "includes error metadata in response" do
    error = error_class.new("Test error message")

    result = service.send(
      handler_method,
      error,
      store_user,
      admin&.id,
      request_metadata
    )

    expect(result).to include(:success, :error, :details)
  end
end

RSpec.shared_examples "user eligibility validation" do
  let(:service) { described_class.new }
  let(:store) { build_stubbed(:store) }

  context "with valid user states" do
    it "passes validation for active user" do
      active_user = build_stubbed(:store_user, active: true, locked_at: nil, store: store)

      expect {
        service.send(:validate_user_eligibility, active_user)
      }.not_to raise_error
    end

    it "allows password expired users (temp password authentication use case)" do
      password_expired_user = build_stubbed(:store_user, :password_expired, store: store)

      expect {
        service.send(:validate_user_eligibility, password_expired_user)
      }.not_to raise_error
    end
  end

  context "with invalid user states" do
    it "raises UserIneligibleError for inactive user" do
      inactive_user = build_stubbed(:store_user, active: false, store: store)

      expect {
        service.send(:validate_user_eligibility, inactive_user)
      }.to raise_error(EmailAuthService::UserIneligibleError, "User account is not active")
    end

    it "raises UserIneligibleError for locked user" do
      locked_user = build_stubbed(:store_user, active: true, locked_at: 1.hour.ago, store: store)

      expect {
        service.send(:validate_user_eligibility, locked_user)
      }.to raise_error(EmailAuthService::UserIneligibleError, "User account is locked")
    end
  end
end

RSpec.shared_examples "memory-safe operation" do |operation_block, memory_limit_mb = 10|
  it "operates within memory constraints" do
    initial_memory = get_memory_usage

    operation_block.call

    final_memory = get_memory_usage
    memory_increase = final_memory - initial_memory

    expect(memory_increase).to be < (memory_limit_mb * 1024 * 1024)
  end

  private

  def get_memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i * 1024
  rescue
    0
  end
end

RSpec.shared_examples "concurrent operation safety" do |operation_block, thread_count = 5|
  it "handles concurrent operations safely" do
    threads = thread_count.times.map do |i|
      Thread.new do
        operation_block.call(i)
      end
    end

    results = threads.map(&:value)

    # All operations should complete without error
    expect(results).to all(be_present)

    # Results should be consistent (specific checks depend on operation)
    expect(results.size).to eq(thread_count)
  end
end

RSpec.shared_examples "configuration-dependent behavior" do |config_key, enabled_behavior, disabled_behavior|
  let(:service) { described_class.new }

  context "when #{config_key} is enabled" do
    before { service.config.send("#{config_key}=", true) }

    it "executes enabled behavior" do
      enabled_behavior.call(service)
    end
  end

  context "when #{config_key} is disabled" do
    before { service.config.send("#{config_key}=", false) }

    it "executes disabled behavior" do
      disabled_behavior.call(service)
    end
  end
end

RSpec.shared_examples "rate limit cache management" do
  let(:service) { described_class.new }

  it "manages cache memory efficiently" do
    initial_cache_size = service.instance_variable_get(:@rate_limit_cache)&.size || 0

    # Create many cache entries
    100.times do |i|
      key = "cache_test_key_#{i}"
      service.send(:redis_increment_with_expiry, key, 1.hour)
    end

    cache = service.instance_variable_get(:@rate_limit_cache)
    current_cache_size = cache&.size || 0

    expect(current_cache_size).to be > initial_cache_size
    expect(current_cache_size).to be < 1000  # Should not grow unbounded
  end

  it "handles expired entries correctly" do
    key = "expired_test_key"

    # Create expired entry
    service.send(:redis_increment_with_expiry, key, -1.hour)

    # Access should return 0 and clean up
    count = service.send(:get_rate_limit_count, key)
    expect(count).to eq(0)
  end
end

RSpec.shared_examples "edge case resilience" do |operation_method|
  let(:service) { described_class.new }

  it "handles nil parameters gracefully" do
    expect {
      service.send(operation_method, nil, nil)
    }.not_to raise_error
  end

  it "handles empty string parameters gracefully" do
    expect {
      service.send(operation_method, "", "")
    }.not_to raise_error
  end

  it "handles large input parameters gracefully" do
    large_param = "a" * 1000
    expect {
      service.send(operation_method, large_param, large_param)
    }.not_to raise_error
  end
end

# ============================================================================
# 使用例とベストプラクティス
# ============================================================================
#
# # 基本的な使用
# RSpec.describe EmailAuthService do
#   include_examples "rate limit validation behavior", :validate_rate_limit
#   include_examples "security logging behavior", "test_event"
#   include_examples "user eligibility validation"
# end
#
# # エラーハンドラーテスト
# include_examples "error handler behavior",
#   :handle_generation_error,
#   EmailAuthService::TempPasswordGenerationError,
#   "temp_password_generation_failed"
#
# # メモリ安全性テスト
# include_examples "memory-safe operation", -> {
#   service.generate_and_send_temp_password(user, request_metadata: metadata)
# }, 5  # 5MB limit
#
# # 並行処理安全性テスト
# include_examples "concurrent operation safety", ->(i) {
#   service.rate_limit_check("user#{i}@example.com", "192.168.1.#{100 + i}")
# }, 10  # 10 threads
# ============================================================================
