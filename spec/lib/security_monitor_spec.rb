# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecurityMonitor do
  let(:monitor) { described_class.new }
  let(:mock_request) do
    double('request',
      user_agent: 'Mozilla/5.0',
      path: '/test',
      query_string: 'param=value',
      content_length: 1000,
      referer: 'http://example.com',
      request_method: 'GET',
      env: { 'HTTP_X_FORWARDED_FOR' => '192.168.1.1' },
      remote_ip: '192.168.1.1'
    )
  end

  describe 'singleton compatibility' do
    it 'maintains singleton instance behavior' do
      instance1 = SecurityMonitor.instance
      instance2 = SecurityMonitor.instance
      expect(instance1).to eq(instance2)
    end
  end

  describe '#analyze_request' do
    context 'when IP is not blocked' do
      before do
        allow(monitor.storage).to receive(:is_blocked?).and_return(false)
        allow(monitor.detector).to receive(:detect_threats).and_return([])
        allow(monitor.storage).to receive(:update_statistics)
      end

      it 'returns empty array for clean request' do
        result = monitor.analyze_request(mock_request)
        expect(result).to be_empty
      end

      it 'updates request statistics' do
        expect(monitor.storage).to receive(:update_statistics)
        monitor.analyze_request(mock_request)
      end
    end

    context 'when IP is blocked' do
      before do
        allow(monitor.storage).to receive(:is_blocked?).and_return(true)
      end

      it 'returns empty array without processing' do
        result = monitor.analyze_request(mock_request)
        expect(result).to be_empty
      end
    end

    context 'when threats are detected' do
      before do
        allow(monitor.storage).to receive(:is_blocked?).and_return(false)
        allow(monitor.detector).to receive(:detect_threats).and_return([ :sql_injection ])
        allow(monitor.detector).to receive(:determine_severity).and_return(:critical)
        allow(monitor.event_handler).to receive(:handle_threat)
        allow(monitor.storage).to receive(:update_statistics)
      end

      it 'handles the threat through event handler' do
        expect(monitor.event_handler).to receive(:handle_threat).with(:critical, hash_including(
          ip: '192.168.1.1',
          threats: [ :sql_injection ],
          severity: :critical
        ))
        monitor.analyze_request(mock_request)
      end
    end
  end

  describe '#track_login_attempt' do
    it 'delegates to login tracker' do
      expect(monitor.login_tracker).to receive(:track_login_attempt)
        .with('192.168.1.1', 'user@example.com', success: true, user_agent: 'Mozilla/5.0')

      monitor.track_login_attempt('192.168.1.1', 'user@example.com', success: true, user_agent: 'Mozilla/5.0')
    end
  end

  describe '#is_blocked?' do
    it 'delegates to storage' do
      expect(monitor.storage).to receive(:is_blocked?).with('192.168.1.1')
      monitor.is_blocked?('192.168.1.1')
    end
  end

  describe '#block_ip' do
    it 'delegates to storage with calculated duration' do
      expect(monitor.storage).to receive(:block_ip).with('192.168.1.1', :brute_force, 120)
      monitor.block_ip('192.168.1.1', :brute_force)
    end

    it 'uses custom duration when provided' do
      expect(monitor.storage).to receive(:block_ip).with('192.168.1.1', :brute_force, 60)
      monitor.block_ip('192.168.1.1', :brute_force, 60)
    end
  end

  describe 'class methods' do
    it 'delegates analyze_request to instance' do
      expect_any_instance_of(SecurityMonitor).to receive(:analyze_request).with(mock_request, nil)
      SecurityMonitor.analyze_request(mock_request)
    end

    it 'delegates track_login_attempt to instance' do
      expect_any_instance_of(SecurityMonitor).to receive(:track_login_attempt)
        .with('192.168.1.1', 'user@example.com', success: true, user_agent: nil)

      SecurityMonitor.track_login_attempt('192.168.1.1', 'user@example.com', success: true)
    end

    it 'delegates is_blocked? to instance' do
      expect_any_instance_of(SecurityMonitor).to receive(:is_blocked?).with('192.168.1.1')
      SecurityMonitor.is_blocked?('192.168.1.1')
    end
  end
end
