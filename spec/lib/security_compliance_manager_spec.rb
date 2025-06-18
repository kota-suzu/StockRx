# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecurityComplianceManager do
  let(:manager) { described_class.instance }
  let(:admin_user) { create(:admin) }

  describe 'singleton pattern' do
    it 'returns the same instance' do
      manager1 = described_class.instance
      manager2 = described_class.instance
      expect(manager1).to eq(manager2)
    end
  end

  describe '#mask_credit_card' do
    context 'with valid credit card numbers' do
      it 'masks 16-digit card number correctly' do
        card_number = '4111111111111111'
        result = manager.mask_credit_card(card_number)
        expect(result).to eq('4111****1111')
      end

      it 'masks 15-digit card number correctly' do
        card_number = '378282246310005'
        result = manager.mask_credit_card(card_number)
        expect(result).to eq('3782****0005')
      end
    end

    context 'with invalid card numbers' do
      it 'returns [INVALID] for non-numeric strings' do
        result = manager.mask_credit_card('invalid-card')
        expect(result).to eq('[INVALID]')
      end

      it 'returns [INVALID] for empty strings' do
        result = manager.mask_credit_card('')
        expect(result).to eq('[INVALID]')
      end

      it 'returns [INVALID] for nil' do
        result = manager.mask_credit_card(nil)
        expect(result).to eq('[INVALID]')
      end
    end
  end

  describe '#encrypt_sensitive_data and #decrypt_sensitive_data' do
    let(:test_data) { 'sensitive information' }

    it 'encrypts and decrypts data successfully' do
      encrypted = manager.encrypt_sensitive_data(test_data)
      decrypted = manager.decrypt_sensitive_data(encrypted)

      expect(encrypted).not_to eq(test_data)
      expect(decrypted).to eq(test_data)
      expect(encrypted).to match(/^[A-Za-z0-9+\/]+=*$/) # Base64 format
    end

    it 'uses different encryption keys for different contexts' do
      encrypted1 = manager.encrypt_sensitive_data(test_data, context: 'card_data')
      encrypted2 = manager.encrypt_sensitive_data(test_data, context: 'personal_data')

      expect(encrypted1).not_to eq(encrypted2)

      decrypted1 = manager.decrypt_sensitive_data(encrypted1, context: 'card_data')
      decrypted2 = manager.decrypt_sensitive_data(encrypted2, context: 'personal_data')

      expect(decrypted1).to eq(test_data)
      expect(decrypted2).to eq(test_data)
    end

    it 'raises error for empty data' do
      expect {
        manager.encrypt_sensitive_data('')
      }.to raise_error(SecurityComplianceManager::EncryptionError, 'データが空です')
    end

    it 'raises error for invalid encrypted data' do
      expect {
        manager.decrypt_sensitive_data('invalid-encrypted-data')
      }.to raise_error(SecurityComplianceManager::EncryptionError, '復号化に失敗しました')
    end
  end

  describe '#anonymize_personal_data' do
    let(:user) { create(:admin, name: 'Test User', email: 'test@example.com') }

    it 'anonymizes personal data successfully' do
      result = manager.anonymize_personal_data(user)

      expect(result[:success]).to be true
      expect(result[:anonymized_fields]).to include('name', 'email')

      user.reload
      expect(user.name).not_to eq('Test User')
      expect(user.email).not_to eq('test@example.com')
      expect(user.name).to start_with('匿名ユーザー')
      expect(user.email).to end_with('@example.com')
    end

    it 'returns error for nil user' do
      result = manager.anonymize_personal_data(nil)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('ユーザーが見つかりません')
    end
  end

  describe '#within_retention_period?' do
    it 'returns true for data within retention period' do
      recent_date = 6.months.ago
      result = manager.within_retention_period?('customer_data', recent_date)
      expect(result).to be true
    end

    it 'returns false for data beyond retention period' do
      old_date = 4.years.ago
      result = manager.within_retention_period?('customer_data', old_date)
      expect(result).to be false
    end

    it 'returns true for unknown data types' do
      recent_date = 6.months.ago
      result = manager.within_retention_period?('unknown_type', recent_date)
      expect(result).to be true
    end
  end

  describe '#secure_compare' do
    it 'returns true for identical strings' do
      result = manager.secure_compare('password123', 'password123')
      expect(result).to be true
    end

    it 'returns false for different strings' do
      result = manager.secure_compare('password123', 'password456')
      expect(result).to be false
    end

    it 'returns false for different length strings' do
      result = manager.secure_compare('short', 'longer_string')
      expect(result).to be false
    end

    it 'returns false when one string is nil' do
      result = manager.secure_compare('test', nil)
      expect(result).to be false
    end

    it 'takes consistent time regardless of input' do
      # タイミング攻撃対策のテスト（実行時間の一貫性）
      times = []

      10.times do
        start_time = Time.current
        manager.secure_compare('test_string', 'different_string')
        end_time = Time.current
        times << (end_time - start_time)
      end

      # 実行時間のばらつきが小さいことを確認
      avg_time = times.sum / times.length
      times.each do |time|
        expect((time - avg_time).abs).to be < 0.01 # 10ms以内のばらつき
      end
    end
  end

  describe '#apply_authentication_delay' do
    it 'applies increasing delays for multiple attempts' do
      start_time = Time.current
      manager.apply_authentication_delay(3, 'test_user')
      end_time = Time.current

      # 3回目の試行では3秒の遅延が適用される
      expect(end_time - start_time).to be >= 3.0
      expect(end_time - start_time).to be < 3.2 # 多少のマージン
    end

    it 'does not delay for first attempt' do
      start_time = Time.current
      manager.apply_authentication_delay(1, 'test_user')
      end_time = Time.current

      expect(end_time - start_time).to be < 0.1
    end
  end

  describe '#within_rate_limit?' do
    let(:identifier) { 'test_user_123' }
    let(:action) { 'login_attempts' }

    before do
      # キャッシュをクリア
      Rails.cache.clear
    end

    it 'allows requests within rate limit' do
      3.times do
        result = manager.within_rate_limit?(action, identifier)
        expect(result).to be true
      end
    end

    it 'blocks requests exceeding rate limit' do
      # 制限まで実行
      5.times do
        manager.within_rate_limit?(action, identifier)
      end

      # 制限を超えた場合はfalseを返す
      result = manager.within_rate_limit?(action, identifier)
      expect(result).to be false
    end

    it 'allows requests for unknown actions' do
      result = manager.within_rate_limit?('unknown_action', identifier)
      expect(result).to be true
    end
  end

  describe '#log_pci_dss_event' do
    it 'creates a compliance audit log entry' do
      expect {
        manager.log_pci_dss_event(
          'card_data_access',
          admin_user,
          {
            ip_address: '192.168.1.1',
            result: 'success'
          }
        )
      }.to change(ComplianceAuditLog, :count).by(1)

      log = ComplianceAuditLog.last
      expect(log.event_type).to eq('card_data_access')
      expect(log.compliance_standard).to eq('PCI_DSS')
      expect(log.user).to eq(admin_user)
    end
  end

  describe '#log_gdpr_event' do
    it 'creates a GDPR compliance audit log entry' do
      expect {
        manager.log_gdpr_event(
          'data_anonymization',
          admin_user,
          {
            anonymized_fields: [ 'name', 'email' ],
            reason: 'user_request'
          }
        )
      }.to change(ComplianceAuditLog, :count).by(1)

      log = ComplianceAuditLog.last
      expect(log.event_type).to eq('data_anonymization')
      expect(log.compliance_standard).to eq('GDPR')
      expect(log.user).to eq(admin_user)
    end
  end

  describe '#process_data_deletion_request' do
    let(:user_with_logs) { create(:admin) }

    before do
      # テスト用の在庫ログを作成
      create_list(:inventory_log, 3, admin: user_with_logs)
    end

    it 'processes data deletion request successfully' do
      result = manager.process_data_deletion_request(user_with_logs)

      expect(result[:success]).to be true
      expect(result[:summary]).to include(:user_id, :request_type, :deleted_records)
    end

    it 'returns error for nil user' do
      result = manager.process_data_deletion_request(nil)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('ユーザーが見つかりません')
    end
  end

  describe 'compliance status checks' do
    it 'initializes compliance status' do
      expect(manager.compliance_status).to include(:pci_dss, :gdpr, :timing_protection)
      expect(manager.last_audit_date).to be_present
    end
  end

  describe 'error handling' do
    it 'handles encryption errors gracefully' do
      # OpenSSLエラーをシミュレート
      allow(OpenSSL::Cipher).to receive(:new).and_raise(OpenSSL::Cipher::CipherError.new("Test error"))

      expect {
        manager.encrypt_sensitive_data('test data')
      }.to raise_error(SecurityComplianceManager::EncryptionError, '暗号化に失敗しました')
    end

    it 'handles decryption errors gracefully' do
      expect {
        manager.decrypt_sensitive_data('invalid_base64_!@#')
      }.to raise_error(SecurityComplianceManager::EncryptionError, '復号化に失敗しました')
    end
  end

  describe 'configuration constants' do
    it 'has valid PCI DSS configuration' do
      expect(SecurityComplianceManager::PCI_DSS_CONFIG).to include(
        :card_number_mask_pattern,
        :encryption_algorithm,
        :card_data_access_roles
      )
    end

    it 'has valid GDPR configuration' do
      expect(SecurityComplianceManager::GDPR_CONFIG).to include(
        :personal_data_fields,
        :data_retention_periods,
        :consent_required_actions
      )
    end

    it 'has valid timing attack protection configuration' do
      expect(SecurityComplianceManager::TIMING_ATTACK_CONFIG).to include(
        :minimum_execution_time,
        :authentication_delays,
        :rate_limits
      )
    end
  end
end
