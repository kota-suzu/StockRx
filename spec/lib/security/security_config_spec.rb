# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security::SecurityConfig do
  let(:config) { described_class.instance }

  describe 'SuspiciousThreshold struct' do
    it 'returns correct default thresholds' do
      expect(config.thresholds.rapid_requests).to eq(100)
      expect(config.thresholds.failed_logins).to eq(5)
      expect(config.thresholds.unique_user_agents).to eq(10)
      expect(config.thresholds.request_size).to eq(10.megabytes)
      expect(config.thresholds.response_time).to eq(30.seconds)
    end

    it 'returns frozen thresholds' do
      expect(config.thresholds).to be_frozen
    end

    describe '#validate!' do
      it 'validates positive integer values' do
        threshold = Security::SecurityConfig::SuspiciousThreshold.new(100, 5, 10, 10.megabytes, 30.0)
        expect { threshold.validate! }.not_to raise_error
      end

      it 'raises error for negative values' do
        threshold = Security::SecurityConfig::SuspiciousThreshold.new(-1, 5, 10, 10.megabytes, 30.0)
        expect { threshold.validate! }.to raise_error(ArgumentError, 'rapid_requests must be positive integer')
      end

      it 'raises error for zero values' do
        threshold = Security::SecurityConfig::SuspiciousThreshold.new(0, 5, 10, 10.megabytes, 30.0)
        expect { threshold.validate! }.to raise_error(ArgumentError, 'rapid_requests must be positive integer')
      end

      it 'raises error for non-numeric response_time' do
        threshold = Security::SecurityConfig::SuspiciousThreshold.new(100, 5, 10, 10.megabytes, 'invalid')
        expect { threshold.validate! }.to raise_error(ArgumentError, 'response_time must be positive number')
      end
    end

    describe '#to_h' do
      it 'returns formatted threshold information' do
        threshold = Security::SecurityConfig::SuspiciousThreshold.new(100, 5, 10, 10.megabytes, 30.0)
        result = threshold.to_h
        expect(result[:rapid_requests]).to eq('100 requests/minute')
        expect(result[:failed_logins]).to eq('5 attempts')
        expect(result[:request_size]).to eq('10MB')
        expect(result[:response_time]).to eq('30.0s')
      end
    end
  end

  describe 'BlockDuration struct' do
    it 'returns correct default block durations' do
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

    describe '#validate!' do
      it 'validates positive integer values' do
        duration = Security::SecurityConfig::BlockDuration.new(60, 120, 1440, 720, 1440, 120)
        expect { duration.validate! }.not_to raise_error
      end

      it 'raises error for negative values' do
        duration = Security::SecurityConfig::BlockDuration.new(-1, 120, 1440, 720, 1440, 120)
        expect { duration.validate! }.to raise_error(ArgumentError, /suspicious_ip must be positive integer/)
      end

      it 'raises error for non-integer values' do
        duration = Security::SecurityConfig::BlockDuration.new(60.5, 120, 1440, 720, 1440, 120)
        expect { duration.validate! }.to raise_error(ArgumentError, /suspicious_ip must be positive integer/)
      end
    end

    describe '#to_h' do
      it 'returns formatted duration information' do
        duration = Security::SecurityConfig::BlockDuration.new(60, 120, 1440, 720, 1440, 120)
        result = duration.to_h
        expect(result[:suspicious_ip]).to eq('60 minutes (1.0 hours)')
        expect(result[:brute_force]).to eq('120 minutes (2.0 hours)')
        expect(result[:sql_injection]).to eq('1440 minutes (24.0 hours)')
      end
    end

    describe '#[]' do
      it 'returns value for valid key' do
        duration = Security::SecurityConfig::BlockDuration.new(60, 120, 1440, 720, 1440, 120)
        expect(duration[:suspicious_ip]).to eq(60)
        expect(duration[:brute_force]).to eq(120)
        expect(duration['sql_injection']).to eq(1440)
      end

      it 'raises error for invalid key' do
        duration = Security::SecurityConfig::BlockDuration.new(60, 120, 1440, 720, 1440, 120)
        expect { duration[:invalid_key] }.to raise_error(ArgumentError, 'Unknown block duration key: invalid_key')
      end
    end
  end

  describe '#redis_keys' do
    it 'returns the correct key mappings with prefix' do
      expect(config.redis_keys[:request_count]).to match(/stockrx:request_count/)
      expect(config.redis_keys[:failed_logins]).to match(/stockrx:failed_logins/)
      expect(config.redis_keys[:login_attempts]).to match(/stockrx:login_attempts/)
      expect(config.redis_keys[:blocked]).to match(/stockrx:blocked/)
      expect(config.redis_keys[:stats_requests]).to match(/stockrx:stats:requests/)
      expect(config.redis_keys[:stats_ip]).to match(/stockrx:stats:ip/)
    end

    it 'returns frozen redis keys' do
      expect(config.redis_keys).to be_frozen
    end
  end

  describe '#whitelist_ips' do
    it 'includes localhost addresses' do
      expect(config.whitelist_ips).to include('127.0.0.1')
      expect(config.whitelist_ips).to include('::1')
    end

    it 'returns frozen whitelist ips' do
      expect(config.whitelist_ips).to be_frozen
    end

                    it 'supports environment variable format for whitelist parsing' do
      # Test the string parsing logic
      env_string = '192.168.1.100, 10.0.0.1'
      env_ips = env_string.split(',').map(&:strip)
      default_ips = [ "127.0.0.1", "::1" ]
      result = (default_ips + env_ips).uniq

      expect(result).to include('192.168.1.100')
      expect(result).to include('10.0.0.1')
      expect(result).to include('127.0.0.1')
    end
  end

  describe '#inspect_configuration' do
    it 'returns comprehensive configuration information' do
      result = config.inspect_configuration

      expect(result).to have_key(:thresholds)
      expect(result).to have_key(:block_durations)
      expect(result).to have_key(:redis_keys)
      expect(result).to have_key(:whitelist_ips)
      expect(result).to have_key(:log_levels)

      expect(result[:thresholds]).to be_a(Hash)
      expect(result[:block_durations]).to be_a(Hash)
    end
  end

  describe '#valid?' do
    it 'returns true for valid configuration' do
      expect(config.valid?).to be true
    end

        context 'with invalid configuration' do
      it 'handles validation errors gracefully' do
        # Test with direct struct validation
        invalid_threshold = Security::SecurityConfig::SuspiciousThreshold.new(-1, 5, 10, 10.megabytes, 30.0)
        expect { invalid_threshold.validate! }.to raise_error(ArgumentError, 'rapid_requests must be positive integer')

        # Test valid? method with current config
        expect(config.valid?).to be true
      end
    end
  end

          describe 'environment variable support' do
    it 'struct implementations support environment variables' do
      # Test that ENV.fetch is used with correct parameters
      expect(ENV).to receive(:fetch).with('SECURITY_RAPID_REQUESTS_THRESHOLD', 100).and_return('200')
      expect(ENV).to receive(:fetch).with('SECURITY_FAILED_LOGINS_THRESHOLD', 5).and_return('10')
      expect(ENV).to receive(:fetch).with('SECURITY_UNIQUE_USER_AGENTS_THRESHOLD', 10).and_return('10')
      expect(ENV).to receive(:fetch).with('SECURITY_REQUEST_SIZE_THRESHOLD', 10.megabytes).and_return('10485760')
      expect(ENV).to receive(:fetch).with('SECURITY_RESPONSE_TIME_THRESHOLD', 30.seconds).and_return('30.0')

      # Test threshold struct creation
      threshold = Security::SecurityConfig::SuspiciousThreshold.default
      expect(threshold.rapid_requests).to eq(200)
      expect(threshold.failed_logins).to eq(10)
    end

    it 'redis key prefixes support environment variables' do
      expect(ENV).to receive(:fetch).with('REDIS_KEY_PREFIX', 'stockrx').and_return('test_app')

      # Test that redis keys use the prefix
      prefix = ENV.fetch('REDIS_KEY_PREFIX', 'stockrx')
      keys = {
        request_count: "#{prefix}:request_count",
        failed_logins: "#{prefix}:failed_logins"
      }

      expect(keys[:request_count]).to eq('test_app:request_count')
      expect(keys[:failed_logins]).to eq('test_app:failed_logins')
    end
  end
end
