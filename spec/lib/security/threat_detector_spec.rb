# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Security::ThreatDetector do
  let(:config) { Security::SecurityConfig.instance }
  let(:storage) { instance_double(Security::SecurityStorage) }
  let(:detector) { described_class.new(config: config, storage: storage) }

  let(:mock_request) do
    double('request',
      user_agent: 'Mozilla/5.0',
      path: '/normal/path',
      query_string: 'param=value',
      content_length: 1000,
      body: double(read: 'normal body', rewind: true),
      env: { 'HTTP_X_FORWARDED_FOR' => '192.168.1.1' },
      remote_ip: '192.168.1.1'
    )
  end

  describe '#detect_threats' do
    before do
      allow(storage).to receive(:increment_counter).and_return(0)
    end

    context 'with normal request' do
      it 'returns empty array' do
        expect(detector.detect_threats(mock_request)).to be_empty
      end
    end

    context 'with rapid requests' do
      before do
        allow(storage).to receive(:increment_counter).and_return(101)
      end

      it 'detects rapid requests threat' do
        threats = detector.detect_threats(mock_request)
        expect(threats).to include(:rapid_requests)
      end
    end

    context 'with suspicious user agent' do
      before do
        allow(mock_request).to receive(:user_agent).and_return('sqlmap/1.0')
      end

      it 'detects suspicious user agent threat' do
        threats = detector.detect_threats(mock_request)
        expect(threats).to include(:suspicious_user_agent)
      end
    end

    context 'with path traversal attempt' do
      before do
        allow(mock_request).to receive(:path).and_return('/../../etc/passwd')
      end

      it 'detects path traversal threat' do
        threats = detector.detect_threats(mock_request)
        expect(threats).to include(:path_traversal)
      end
    end

    context 'with SQL injection attempt' do
      before do
        allow(mock_request).to receive(:query_string).and_return("id=1' OR 1=1--")
      end

      it 'detects SQL injection threat' do
        threats = detector.detect_threats(mock_request)
        expect(threats).to include(:sql_injection)
      end
    end

    context 'with large request' do
      before do
        allow(mock_request).to receive(:content_length).and_return(20.megabytes)
      end

      it 'detects large request threat' do
        threats = detector.detect_threats(mock_request)
        expect(threats).to include(:large_request)
      end
    end

    context 'with whitelisted IP' do
      before do
        allow(mock_request).to receive(:env).and_return({ 'HTTP_X_FORWARDED_FOR' => '127.0.0.1' })
        allow(mock_request).to receive(:remote_ip).and_return('127.0.0.1')
        allow(storage).to receive(:increment_counter).and_return(101)
      end

      it 'returns empty array for whitelisted IP' do
        expect(detector.detect_threats(mock_request)).to be_empty
      end
    end
  end

  describe '#determine_severity' do
    it 'returns critical for SQL injection' do
      expect(detector.determine_severity([ :sql_injection ])).to eq(:critical)
    end

    it 'returns critical for path traversal' do
      expect(detector.determine_severity([ :path_traversal ])).to eq(:critical)
    end

    it 'returns high for rapid requests with multiple threats' do
      expect(detector.determine_severity([ :rapid_requests, :large_request ])).to eq(:high)
    end

    it 'returns medium for single non-critical threat' do
      expect(detector.determine_severity([ :suspicious_user_agent ])).to eq(:medium)
    end
  end
end
