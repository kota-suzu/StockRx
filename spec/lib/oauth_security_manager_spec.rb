# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OauthSecurityManager, type: :lib do
  let(:request) { double('Request', remote_ip: '192.168.1.1', user_agent: 'Test Agent', host: 'localhost', host_with_port: 'localhost:3000', protocol: 'http://') }
  let(:session) { {} }
  let(:manager) { described_class.new(request, session) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(Rails.cache).to receive(:read).and_return(0)
    allow(Rails.cache).to receive(:write)

    # Mock Rails environment
    allow(Rails.env).to receive(:production?).and_return(false)
  end

  describe '#initialize' do
    it 'sets request and session' do
      expect(manager.request).to eq(request)
      expect(manager.session).to eq(session)
    end
  end

  describe '#validate_oauth_initiation' do
    let(:provider) { :github }
    let(:redirect_uri) { 'http://localhost:3000/admin/auth/github/callback' }

    context 'with valid parameters' do
      before do
        session[:oauth_state_token] = 'valid_token'
        session[:oauth_state_expires] = 5.minutes.from_now
      end

      it 'returns true when all validations pass' do
        result = manager.validate_oauth_initiation(provider, redirect_uri)
        expect(result).to be true
      end

      it 'logs successful initiation' do
        manager.validate_oauth_initiation(provider, redirect_uri)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            event: 'oauth_initiation',
            provider: provider
          ).to_json
        )
      end
    end

    context 'with invalid CSRF token' do
      it 'returns false and logs warning' do
        session[:oauth_state_token] = nil

        result = manager.validate_oauth_initiation(provider, redirect_uri)
        expect(result).to be false

        expect(Rails.logger).to have_received(:warn)
      end
    end

    context 'with expired CSRF token' do
      it 'returns false when token is expired' do
        session[:oauth_state_token] = 'valid_token'
        session[:oauth_state_expires] = 1.minute.ago

        result = manager.validate_oauth_initiation(provider, redirect_uri)
        expect(result).to be false
      end
    end

    context 'with invalid redirect URI' do
      it 'rejects non-HTTPS in production' do
        allow(Rails.env).to receive(:production?).and_return(true)

        result = manager.validate_oauth_initiation(provider, 'http://example.com/callback')
        expect(result).to be false
      end

      it 'rejects unauthorized domains' do
        result = manager.validate_oauth_initiation(provider, 'https://malicious.com/callback')
        expect(result).to be false
      end

      it 'rejects invalid paths' do
        result = manager.validate_oauth_initiation(provider, 'http://localhost:3000/malicious/path')
        expect(result).to be false
      end
    end

    context 'with rate limiting' do
      it 'blocks requests after maximum attempts' do
        allow(Rails.cache).to receive(:read).and_return(described_class::MAX_LOGIN_ATTEMPTS)

        result = manager.validate_oauth_initiation(provider, redirect_uri)
        expect(result).to be false

        expect(Rails.logger).to have_received(:warn).with(
          hash_including(event: 'rate_limit_exceeded').to_json
        )
      end
    end

    context 'with unsupported provider' do
      it 'rejects unsupported providers' do
        result = manager.validate_oauth_initiation(:facebook, redirect_uri)
        expect(result).to be false
      end
    end
  end

  describe '#validate_oauth_callback' do
    let(:auth_hash) do
      {
        provider: 'github',
        uid: '12345',
        info: {
          email: 'user@example.com',
          login: 'testuser',
          name: 'Test User'
        }
      }
    end
    let(:state_token) { 'valid_state_token' }

    before do
      session[:oauth_state_token] = state_token
      session[:oauth_initiated_at] = 30.seconds.ago
    end

    context 'with valid callback data' do
      it 'returns true when all validations pass' do
        result = manager.validate_oauth_callback(auth_hash, state_token)
        expect(result).to be true
      end

      it 'logs successful callback' do
        manager.validate_oauth_callback(auth_hash, state_token)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            event: 'oauth_callback',
            provider: 'github'
          ).to_json
        )
      end
    end

    context 'with invalid auth hash' do
      it 'rejects empty auth hash' do
        result = manager.validate_oauth_callback(nil, state_token)
        expect(result).to be false
      end

      it 'rejects auth hash missing required fields' do
        invalid_auth_hash = { provider: 'github' }
        result = manager.validate_oauth_callback(invalid_auth_hash, state_token)
        expect(result).to be false
      end

      it 'rejects GitHub auth hash with invalid email' do
        auth_hash[:info][:email] = 'invalid-email'
        result = manager.validate_oauth_callback(auth_hash, state_token)
        expect(result).to be false
      end

      it 'rejects GitHub auth hash with non-numeric uid' do
        auth_hash[:uid] = 'invalid-uid'
        result = manager.validate_oauth_callback(auth_hash, state_token)
        expect(result).to be false
      end

      it 'rejects emails from blocked domains' do
        auth_hash[:info][:email] = 'user@tempmail.com'
        result = manager.validate_oauth_callback(auth_hash, state_token)
        expect(result).to be false
      end
    end

    context 'with invalid state token' do
      it 'rejects mismatched state token' do
        result = manager.validate_oauth_callback(auth_hash, 'wrong_token')
        expect(result).to be false
      end

      it 'rejects when stored token is missing' do
        session[:oauth_state_token] = nil
        result = manager.validate_oauth_callback(auth_hash, state_token)
        expect(result).to be false
      end
    end

    context 'with timing attacks' do
      it 'rejects extremely fast callbacks' do
        session[:oauth_initiated_at] = 0.5.seconds.ago
        result = manager.validate_oauth_callback(auth_hash, state_token)
        expect(result).to be false
      end

      it 'rejects extremely slow callbacks' do
        session[:oauth_initiated_at] = 15.minutes.ago
        result = manager.validate_oauth_callback(auth_hash, state_token)
        expect(result).to be false
      end
    end
  end

  describe '#generate_secure_oauth_url' do
    let(:provider) { :github }

    it 'generates secure OAuth URL with state token' do
      url = manager.generate_secure_oauth_url(provider)

      expect(url).to include('/admin/auth/github')
      expect(url).to include('state=')
      expect(url).to include('redirect_uri=')
      expect(url).to include('scope=user:email')

      expect(session[:oauth_state_token]).to be_present
      expect(session[:oauth_state_expires]).to be > Time.current
    end

    it 'includes additional parameters' do
      additional_params = { custom_param: 'value' }
      url = manager.generate_secure_oauth_url(provider, additional_params)

      expect(url).to include('custom_param=value')
    end

    it 'raises error for unsupported provider' do
      expect {
        manager.generate_secure_oauth_url(:facebook)
      }.to raise_error(ArgumentError, 'Unsupported OAuth provider: facebook')
    end
  end

  describe '#record_failed_attempt' do
    it 'records failed attempt with details' do
      reason = 'invalid_credentials'
      details = { error: 'test error' }

      manager.record_failed_attempt(reason, details)

      expect(session[:failed_oauth_attempts]).to be_present
      failure = session[:failed_oauth_attempts].last

      expect(failure[:reason]).to eq(reason)
      expect(failure[:details]).to eq(details)
      expect(failure[:ip_address]).to eq('192.168.1.1')
      expect(failure[:user_agent]).to eq('Test Agent')
    end

    it 'limits stored attempts to 5' do
      7.times { |i| manager.record_failed_attempt("reason_#{i}") }

      expect(session[:failed_oauth_attempts].size).to eq(5)
    end

    it 'logs security event' do
      manager.record_failed_attempt('test_reason')

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(event: 'oauth_security_oauth_failed_attempt').to_json
      )
    end
  end

  describe '#secure_session_reset' do
    before do
      session[:oauth_state_token] = 'token'
      session[:omniauth_provider] = 'github'
      session[:some_other_data] = 'value'
    end

    it 'clears session and regenerates ID' do
      allow(session).to receive(:clear)
      allow(session).to receive(:regenerate_id)

      manager.secure_session_reset

      expect(session).to have_received(:clear)
      expect(session).to have_received(:regenerate_id)
    end

    it 'restores essential OAuth data' do
      session[:omniauth_provider] = 'github'
      session[:oauth_user_id] = 123

      manager.secure_session_reset

      expect(session[:omniauth_provider]).to eq('github')
      expect(session[:oauth_user_id]).to eq(123)
      expect(session[:created_at]).to be_present
      expect(session[:ip_address]).to eq('192.168.1.1')
    end

    it 'logs session reset event' do
      manager.secure_session_reset

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(event: 'oauth_security_session_reset').to_json
      )
    end
  end

  describe 'private methods' do
    describe '#secure_compare' do
      it 'returns true for identical strings' do
        result = manager.send(:secure_compare, 'test', 'test')
        expect(result).to be true
      end

      it 'returns false for different strings' do
        result = manager.send(:secure_compare, 'test', 'different')
        expect(result).to be false
      end

      it 'returns false for strings of different lengths' do
        result = manager.send(:secure_compare, 'short', 'longer string')
        expect(result).to be false
      end
    end

    describe '#sanitize_email' do
      it 'masks email addresses' do
        result = manager.send(:sanitize_email, 'user@example.com')
        expect(result).to eq('u***r@example.com')
      end

      it 'handles short usernames' do
        result = manager.send(:sanitize_email, 'ab@example.com')
        expect(result).to eq('***@example.com')
      end

      it 'handles blank emails' do
        result = manager.send(:sanitize_email, '')
        expect(result).to eq('[BLANK]')
      end
    end

    describe '#sanitize_user_agent' do
      it 'truncates long user agents' do
        long_agent = 'a' * 250
        result = manager.send(:sanitize_user_agent, long_agent)
        expect(result).to eq('a' * 200 + '[TRUNCATED]')
      end

      it 'filters malicious characters' do
        malicious_agent = 'Mozilla<script>alert("xss")</script>'
        result = manager.send(:sanitize_user_agent, malicious_agent)
        expect(result).to eq('Mozilla[FILTERED]script[FILTERED]alert([FILTERED]xss[FILTERED])[FILTERED]/script[FILTERED]')
      end
    end
  end

  describe 'session security validation' do
    it 'validates session timeout' do
      session[:created_at] = 2.hours.ago

      result = manager.send(:validate_session_security)
      expect(result).to be false
    end

    it 'validates IP address consistency' do
      session[:ip_address] = '10.0.0.1'

      result = manager.send(:validate_session_security)
      expect(result).to be false

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(event: 'oauth_security_session_ip_mismatch').to_json
      )
    end
  end
end
