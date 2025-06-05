# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security::SecurityConfig do
  let(:config) { described_class.instance }

  describe 'singleton behavior' do
    it 'returns the same instance' do
      expect(Security::SecurityConfig.instance).to eq(config)
    end
  end

  describe '#thresholds' do
    it 'returns the correct default values' do
      expect(config.thresholds.rapid_requests).to eq(100)
      expect(config.thresholds.failed_logins).to eq(5)
      expect(config.thresholds.unique_user_agents).to eq(10)
      expect(config.thresholds.request_size).to eq(10.megabytes)
      expect(config.thresholds.response_time).to eq(30.seconds)
    end

    it 'returns frozen thresholds' do
      expect(config.thresholds).to be_frozen
    end
  end

  describe '#block_durations' do
    it 'returns the correct default values' do
      expect(config.block_durations.suspicious_ip).to eq(60)
      expect(config.block_durations.brute_force).to eq(120)
      expect(config.block_durations.sql_injection).to eq(1440)
      expect(config.block_durations.path_traversal).to eq(720)
      expect(config.block_durations.critical_threat).to eq(1440)
      expect(config.block_durations.high_threat).to eq(120)
    end

    it 'returns frozen block durations' do
      expect(config.block_durations).to be_frozen
    end
  end

  describe '#redis_keys' do
    it 'returns the correct key mappings' do
      expect(config.redis_keys[:request_count]).to eq("request_count")
      expect(config.redis_keys[:failed_logins]).to eq("failed_logins")
      expect(config.redis_keys[:blocked]).to eq("blocked")
    end

    it 'returns frozen redis keys' do
      expect(config.redis_keys).to be_frozen
    end
  end

  describe '#whitelist_ips' do
    it 'includes localhost addresses' do
      expect(config.whitelist_ips).to include("127.0.0.1", "::1")
    end

    it 'returns frozen whitelist' do
      expect(config.whitelist_ips).to be_frozen
    end
  end
end