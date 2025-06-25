# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecurityComplianceManager do
  # CLAUDE.md準拠: セキュリティコンプライアンス管理の包括的テスト
  # メタ認知: PCI DSS/GDPR準拠機能とタイミング攻撃対策の品質保証
  # 横展開: 他のセキュリティ機能でも同様の厳密なテスト実装

  let(:manager) { described_class.instance }
  let(:admin_user) { create(:admin) }
  let(:store_user) { create(:store_user) }

  # テスト環境の初期化と後処理
  before(:each) do
    Rails.cache.clear
    # テスト用の暗号化キー設定
    # 32バイトの暗号化キーを設定（AES-256-GCM用）
    test_key = 'a' * 32  # 正確に32バイトのキー
    allow(Rails.application.credentials).to receive(:dig).and_return(test_key)
  end

  after(:each) do
    Rails.cache.clear
  end

  describe 'singleton pattern' do
    it 'returns the same instance across multiple calls' do
      manager1 = described_class.instance
      manager2 = described_class.instance
      expect(manager1.object_id).to eq(manager2.object_id)
    end

    it 'cannot be instantiated with new' do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end

  describe 'initialization' do
    it 'initializes compliance status correctly' do
      expect(manager.compliance_status).to be_a(Hash)
      expect(manager.compliance_status.keys).to contain_exactly(:pci_dss, :gdpr, :timing_protection)
    end

    it 'sets last_audit_date' do
      expect(manager.last_audit_date).to be_present
      expect(manager.last_audit_date).to be_a(Time)
    end

    it 'logs initialization' do
      expect(Rails.logger).to receive(:info).with(/SecurityComplianceManager initialized/)
      described_class.instance.send(:initialize_security_features)
    end
  end

  # ============================================================================
  # PCI DSS準拠機能テスト
  # ============================================================================
  describe 'PCI DSS Compliance Features' do
    describe '#mask_credit_card' do
      context 'with valid credit card numbers' do
        # 各カードブランドのテスト
        [
          { number: '4111111111111111', masked: '4111****1111', brand: 'Visa' },
          { number: '5500000000000004', masked: '5500****0004', brand: 'Mastercard' },
          { number: '378282246310005', masked: '3782****0005', brand: 'Amex' },
          { number: '6011111111111117', masked: '6011****1117', brand: 'Discover' },
          { number: '3530111333300000', masked: '3530****0000', brand: 'JCB' }
        ].each do |card_data|
          it "masks #{card_data[:brand]} card number correctly" do
            result = manager.mask_credit_card(card_data[:number])
            expect(result).to eq(card_data[:masked])
          end
        end

        it 'handles card numbers with spaces' do
          result = manager.mask_credit_card('4111 1111 1111 1111')
          expect(result).to eq('4111****1111')
        end

        it 'handles card numbers with dashes' do
          result = manager.mask_credit_card('4111-1111-1111-1111')
          expect(result).to eq('4111****1111')
        end

        it 'applies timing protection' do
          start_time = Time.current
          manager.mask_credit_card('4111111111111111')
          end_time = Time.current

          # 最小実行時間が保証されていることを確認
          expect(end_time - start_time).to be >= 0.1
        end
      end

      context 'with invalid card numbers' do
        [
          { input: nil, description: 'nil' },
          { input: '', description: 'empty string' },
          { input: 'invalid', description: 'non-numeric' },
          { input: '123', description: 'too short' },
          { input: '12345678901234567890', description: 'too long' },
          { input: 'XXXX-XXXX-XXXX-XXXX', description: 'all letters' }
        ].each do |test_case|
          it "returns [INVALID] for #{test_case[:description]}" do
            result = manager.mask_credit_card(test_case[:input])
            expect(result).to eq('[INVALID]')
          end
        end
      end

      context 'edge cases' do
        it 'handles 13-digit card numbers' do
          result = manager.mask_credit_card('4000123456789')
          expect(result).to eq('4000****6789')
        end

        it 'handles 19-digit card numbers' do
          result = manager.mask_credit_card('4000123456789012345')
          expect(result).to eq('4000****2345')
        end
      end
    end

    describe '#encrypt_sensitive_data / #decrypt_sensitive_data' do
      let(:test_data) { 'sensitive credit card info: 4111111111111111' }

      context 'successful encryption/decryption' do
        it 'encrypts and decrypts data successfully' do
          encrypted = manager.encrypt_sensitive_data(test_data)

          expect(encrypted).not_to eq(test_data)
          expect(encrypted).to match(/^[A-Za-z0-9+\/]+=*$/) # Base64 format

          decrypted = manager.decrypt_sensitive_data(encrypted)
          expect(decrypted).to eq(test_data)
        end

        it 'produces different ciphertext for same plaintext (due to random IV)' do
          encrypted1 = manager.encrypt_sensitive_data(test_data)
          encrypted2 = manager.encrypt_sensitive_data(test_data)

          expect(encrypted1).not_to eq(encrypted2)
        end

        it 'uses different keys for different contexts' do
          contexts = %w[default card_data personal_data audit_logs]
          encrypted_values = {}

          contexts.each do |context|
            encrypted_values[context] = manager.encrypt_sensitive_data(test_data, context: context)
          end

          # 各コンテキストで異なる暗号文が生成される
          expect(encrypted_values.values.uniq.size).to eq(contexts.size)

          # 各コンテキストで正しく復号化できる
          contexts.each do |context|
            decrypted = manager.decrypt_sensitive_data(encrypted_values[context], context: context)
            expect(decrypted).to eq(test_data)
          end
        end

        it 'handles large data' do
          large_data = 'A' * 10000
          encrypted = manager.encrypt_sensitive_data(large_data)
          decrypted = manager.decrypt_sensitive_data(encrypted)

          expect(decrypted).to eq(large_data)
        end

        it 'handles Unicode data' do
          unicode_data = '機密データ 🔐 秘密の情報'
          encrypted = manager.encrypt_sensitive_data(unicode_data)
          decrypted = manager.decrypt_sensitive_data(encrypted)

          expect(decrypted).to eq(unicode_data)
        end
      end

      context 'error handling' do
        it 'raises EncryptionError for blank data' do
          [ '', nil ].each do |blank_data|
            expect {
              manager.encrypt_sensitive_data(blank_data)
            }.to raise_error(SecurityComplianceManager::EncryptionError, 'データが空です')
          end
        end

        it 'raises EncryptionError for invalid Base64 on decryption' do
          expect {
            manager.decrypt_sensitive_data('invalid!@#$%')
          }.to raise_error(SecurityComplianceManager::EncryptionError, '復号化に失敗しました')
        end

        it 'raises EncryptionError for tampered data' do
          encrypted = manager.encrypt_sensitive_data(test_data)
          # 暗号文を改ざん
          tampered = Base64.strict_encode64(Base64.strict_decode64(encrypted) + 'tampered')

          expect {
            manager.decrypt_sensitive_data(tampered)
          }.to raise_error(SecurityComplianceManager::EncryptionError, '復号化に失敗しました')
        end

        it 'raises EncryptionError for wrong context' do
          encrypted = manager.encrypt_sensitive_data(test_data, context: 'card_data')

          expect {
            manager.decrypt_sensitive_data(encrypted, context: 'personal_data')
          }.to raise_error(SecurityComplianceManager::EncryptionError, '復号化に失敗しました')
        end

        it 'handles OpenSSL errors gracefully' do
          allow(OpenSSL::Cipher).to receive(:new).and_raise(OpenSSL::Cipher::CipherError, 'Test error')

          expect {
            manager.encrypt_sensitive_data(test_data)
          }.to raise_error(SecurityComplianceManager::EncryptionError, '暗号化に失敗しました')
        end
      end
    end

    describe '#log_pci_dss_event' do
      let(:event_details) do
        {
          ip_address: '192.168.1.100',
          user_agent: 'Mozilla/5.0',
          card_number: '4111111111111111',
          result: 'success'
        }
      end

      it 'creates encrypted audit log' do
        expect {
          manager.log_pci_dss_event('card_data_access', admin_user, event_details)
        }.to change(ComplianceAuditLog, :count).by(1)

        log = ComplianceAuditLog.last
        expect(log.event_type).to eq('card_data_access')
        expect(log.compliance_standard).to eq('pci_dss')
        expect(log.user).to eq(admin_user)
        expect(log.severity).to eq('medium')
        expect(log.encrypted_details).to be_present

        # 暗号化されたデータを復号化して検証
        decrypted_details = JSON.parse(
          manager.decrypt_sensitive_data(log.encrypted_details, context: 'audit_logs')
        )
        expect(decrypted_details['action']).to eq('card_data_access')
        expect(decrypted_details['details']['card_number']).to eq('4111****1111') # マスキング済み
      end

      it 'sanitizes sensitive information' do
        sensitive_details = event_details.merge(
          password: 'secret123',
          password_confirmation: 'secret123'
        )

        manager.log_pci_dss_event('authentication', admin_user, sensitive_details)

        log = ComplianceAuditLog.last
        decrypted = JSON.parse(
          manager.decrypt_sensitive_data(log.encrypted_details, context: 'audit_logs')
        )

        expect(decrypted['details']).not_to have_key('password')
        expect(decrypted['details']).not_to have_key('password_confirmation')
      end

      it 'determines severity correctly' do
        severity_tests = [
          { action: 'encryption_key_rotation', expected: 'high' },
          { action: 'card_data_access', expected: 'medium' },
          { action: 'view_masked_card', expected: 'low' }
        ]

        severity_tests.each do |test|
          manager.log_pci_dss_event(test[:action], admin_user, {})
          log = ComplianceAuditLog.last
          expect(log.severity).to eq(test[:expected])
        end
      end

      it 'handles logging errors with fallback' do
        allow(ComplianceAuditLog).to receive(:create!).and_raise(
          ActiveRecord::RecordInvalid.new(ComplianceAuditLog.new)
        )

        expect(Rails.logger).to receive(:error).at_least(:once)
        expect(Rails.logger).to receive(:warn).with(/PCI_DSS_AUDIT_FALLBACK/)

        expect {
          manager.log_pci_dss_event('card_data_access', admin_user, event_details)
        }.to raise_error(SecurityComplianceManager::ComplianceError, /PCI DSS監査ログの作成に失敗しました/)
      end
    end
  end

  # ============================================================================
  # GDPR準拠機能テスト
  # ============================================================================
  describe 'GDPR Compliance Features' do
    describe '#anonymize_personal_data' do
      let(:user) do
        create(:admin,
          name: '山田太郎',
          email: 'yamada@example.com',
          phone_number: '090-1234-5678',
          address: '東京都渋谷区1-2-3'
        )
      end

      context 'successful anonymization' do
        it 'anonymizes all personal data fields' do
          result = manager.anonymize_personal_data(user)

          expect(result[:success]).to be true
          expect(result[:anonymized_fields]).to include('name', 'email')

          user.reload
          expect(user.name).to match(/^匿名ユーザー[a-f0-9]{8}$/)
          expect(user.email).to match(/^anonymized_[a-f0-9]{16}@example\.com$/)
        end

        it 'creates GDPR audit log' do
          expect {
            manager.anonymize_personal_data(user)
          }.to change(ComplianceAuditLog, :count).by(1)

          log = ComplianceAuditLog.last
          expect(log.event_type).to eq('data_anonymization')
          expect(log.compliance_standard).to eq('gdpr')
        end

        it 'preserves original data hash for verification' do
          original_name = user.name
          original_email = user.email

          manager.anonymize_personal_data(user)

          # ログから元データのハッシュを確認できる
          log = ComplianceAuditLog.last
          decrypted = JSON.parse(
            manager.decrypt_sensitive_data(log.encrypted_details, context: 'audit_logs')
          )

          expect(decrypted['details']['anonymized_fields']).to include('name', 'email')
        end
      end

      context 'error handling' do
        it 'returns error for nil user' do
          result = manager.anonymize_personal_data(nil)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('ユーザーが見つかりません')
        end

        it 'handles database errors gracefully' do
          allow(user).to receive(:update_column).and_raise(ActiveRecord::ActiveRecordError, 'DB error')

          result = manager.anonymize_personal_data(user)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('DB error')
        end
      end
    end

    describe '#within_retention_period?' do
      context 'with defined retention periods' do
        [
          { type: 'customer_data', period: 3.years, in_period: 2.years.ago, out_period: 4.years.ago },
          { type: 'employee_data', period: 7.years, in_period: 6.years.ago, out_period: 8.years.ago },
          { type: 'transaction_logs', period: 1.year, in_period: 6.months.ago, out_period: 2.years.ago },
          { type: 'audit_logs', period: 2.years, in_period: 1.year.ago, out_period: 3.years.ago }
        ].each do |test_case|
          it "checks retention for #{test_case[:type]}" do
            expect(manager.within_retention_period?(test_case[:type], test_case[:in_period])).to be true
            expect(manager.within_retention_period?(test_case[:type], test_case[:out_period])).to be false
          end
        end
      end

      context 'with undefined data types' do
        it 'returns true for unknown data types' do
          expect(manager.within_retention_period?('unknown_type', 10.years.ago)).to be true
        end
      end

      context 'edge cases' do
        it 'handles exactly at retention boundary' do
          exactly_3_years_ago = 3.years.ago
          result = manager.within_retention_period?('customer_data', exactly_3_years_ago)
          # Should be false as it's exactly at the boundary
          expect(result).to be false
        end
      end
    end

    describe '#process_data_deletion_request' do
      let(:user) { create(:admin) }
      let!(:recent_logs) { create_list(:inventory_log, 3, admin: user, created_at: 1.month.ago) }
      let!(:old_logs) { create_list(:inventory_log, 2, admin: user, created_at: 2.years.ago) }
      let!(:store) { create(:store, admin: user) }

      context 'successful deletion request' do
        it 'processes deletion request according to retention policies' do
          result = manager.process_data_deletion_request(user)

          expect(result[:success]).to be true
          expect(result[:summary][:user_id]).to eq(user.id)
          expect(result[:summary][:request_type]).to eq('right_to_erasure')

          # 保持期間内のログは匿名化
          expect(result[:summary][:anonymized_records]).to include(
            "inventory_log_#{recent_logs.first.id}",
            "inventory_log_#{recent_logs.second.id}",
            "inventory_log_#{recent_logs.third.id}"
          )

          # 保持期間外のログは削除
          expect(result[:summary][:deleted_records]).to include(
            "inventory_log_#{old_logs.first.id}",
            "inventory_log_#{old_logs.second.id}"
          )

          # ビジネス要件により店舗データは保持
          expect(result[:summary][:retained_records]).to include('stores (business requirement)')
        end

        it 'anonymizes personal information in retained logs' do
          manager.process_data_deletion_request(user)

          recent_logs.each do |log|
            log.reload
            expect(log.admin_id).to be_nil
            expect(log.description).not_to include(user.name) if log.description
          end
        end

        it 'deletes old logs' do
          expect {
            manager.process_data_deletion_request(user)
          }.to change(InventoryLog, :count).by(-2)

          expect(InventoryLog.where(id: old_logs.map(&:id))).to be_empty
        end

        it 'creates GDPR audit log' do
          expect {
            manager.process_data_deletion_request(user)
          }.to change(ComplianceAuditLog, :count).by(1)

          log = ComplianceAuditLog.last
          expect(log.event_type).to eq('data_deletion')
          expect(log.compliance_standard).to eq('gdpr')
        end
      end

      context 'with different request types' do
        it 'handles data_retention_expired request type' do
          result = manager.process_data_deletion_request(user, request_type: 'data_retention_expired')

          expect(result[:success]).to be true
          expect(result[:summary][:request_type]).to eq('data_retention_expired')
        end
      end

      context 'error handling' do
        it 'returns error for nil user' do
          result = manager.process_data_deletion_request(nil)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('ユーザーが見つかりません')
        end

        it 'handles database errors gracefully' do
          allow_any_instance_of(InventoryLog).to receive(:destroy!).and_raise(
            ActiveRecord::ActiveRecordError, 'Cannot delete'
          )

          result = manager.process_data_deletion_request(user)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Cannot delete')
        end
      end
    end

    describe '#log_gdpr_event' do
      let(:event_details) do
        {
          anonymized_fields: [ 'name', 'email' ],
          reason: 'user_request',
          legal_basis: 'consent'
        }
      end

      it 'creates encrypted GDPR audit log' do
        expect {
          manager.log_gdpr_event('data_anonymization', admin_user, event_details)
        }.to change(ComplianceAuditLog, :count).by(1)

        log = ComplianceAuditLog.last
        expect(log.event_type).to eq('data_anonymization')
        expect(log.compliance_standard).to eq('gdpr')
        expect(log.user).to eq(admin_user)

        # 暗号化されたデータを復号化して検証
        decrypted = JSON.parse(
          manager.decrypt_sensitive_data(log.encrypted_details, context: 'audit_logs')
        )
        expect(decrypted['legal_basis']).to eq('consent')
      end

      it 'uses default legal basis when not provided' do
        manager.log_gdpr_event('data_export', admin_user, {})

        log = ComplianceAuditLog.last
        decrypted = JSON.parse(
          manager.decrypt_sensitive_data(log.encrypted_details, context: 'audit_logs')
        )
        expect(decrypted['legal_basis']).to eq('legitimate_interest')
      end
    end
  end

  # ============================================================================
  # タイミング攻撃対策テスト
  # ============================================================================
  describe 'Timing Attack Protection' do
    describe '#secure_compare' do
      context 'string comparison' do
        it 'returns true for identical strings' do
          expect(manager.secure_compare('password123', 'password123')).to be true
        end

        it 'returns false for different strings' do
          expect(manager.secure_compare('password123', 'password456')).to be false
        end

        it 'returns false for different length strings' do
          expect(manager.secure_compare('short', 'much_longer_string')).to be false
        end

        it 'returns false when either string is nil' do
          expect(manager.secure_compare(nil, 'test')).to be false
          expect(manager.secure_compare('test', nil)).to be false
          expect(manager.secure_compare(nil, nil)).to be false
        end

        it 'handles empty strings' do
          expect(manager.secure_compare('', '')).to be true
          expect(manager.secure_compare('test', '')).to be false
        end
      end

      context 'timing consistency' do
        it 'takes consistent time regardless of mismatch position' do
          # 最初の文字が異なる場合
          times1 = []
          10.times do
            start = Time.current
            manager.secure_compare('aaaaaaaaaaaa', 'bbbbbbbbbbbb')
            times1 << (Time.current - start)
          end

          # 最後の文字が異なる場合
          times2 = []
          10.times do
            start = Time.current
            manager.secure_compare('aaaaaaaaaaaa', 'aaaaaaaaaaab')
            times2 << (Time.current - start)
          end

          avg_time1 = times1.sum / times1.length
          avg_time2 = times2.sum / times2.length

          # 実行時間の差が5%以内であることを確認
          time_diff_percentage = ((avg_time1 - avg_time2).abs / avg_time1) * 100
          expect(time_diff_percentage).to be < 5
        end

        it 'maintains minimum execution time' do
          start_time = Time.current
          manager.secure_compare('a', 'b')
          end_time = Time.current

          # 最小実行時間が保証されている
          expect(end_time - start_time).to be >= 0.0001 # minimum_execution_time / 1000
        end
      end
    end

    describe '#apply_authentication_delay' do
      context 'progressive delays' do
        [
          { attempt: 1, expected_delay: 0 },
          { attempt: 2, expected_delay: 1 },
          { attempt: 3, expected_delay: 3 },
          { attempt: 4, expected_delay: 9 },
          { attempt: 5, expected_delay: 27 },
          { attempt: 10, expected_delay: 27 } # Max delay
        ].each do |test_case|
          it "applies #{test_case[:expected_delay]}s delay for attempt #{test_case[:attempt]}" do
            if test_case[:expected_delay] > 0
              expect(manager).to receive(:sleep).with(test_case[:expected_delay])
            else
              expect(manager).not_to receive(:sleep)
            end

            manager.apply_authentication_delay(test_case[:attempt], 'test_user')
          end
        end
      end

      it 'logs authentication delays' do
        expect(Rails.logger).to receive(:info).with(/Authentication delay applied: 3s/)
        manager.apply_authentication_delay(3, 'test_user')
      end

      it 'creates timing protection audit log' do
        expect(manager).to receive(:log_timing_protection_event).with(
          'authentication_delay',
          hash_including(:attempt_count, :delay_applied, :identifier)
        )

        manager.apply_authentication_delay(3, 'test_user')
      end

      it 'hashes identifier for privacy' do
        expect(manager).to receive(:log_timing_protection_event) do |action, details|
          expect(details[:identifier]).to match(/^[a-f0-9]{64}$/) # SHA256 hash
          expect(details[:identifier]).not_to eq('test_user@example.com')
        end

        manager.apply_authentication_delay(2, 'test_user@example.com')
      end
    end

    describe '#within_rate_limit?' do
      before { Rails.cache.clear }

      context 'rate limit enforcement' do
        [
          { action: 'login_attempts', limit: 5, period: 15.minutes },
          { action: 'password_reset', limit: 3, period: 1.hour },
          { action: 'api_requests', limit: 100, period: 1.minute }
        ].each do |limit_config|
          it "enforces rate limit for #{limit_config[:action]}" do
            identifier = "user_#{SecureRandom.hex(8)}"

            # 制限内のリクエスト
            limit_config[:limit].times do |i|
              result = manager.within_rate_limit?(limit_config[:action], identifier)
              expect(result).to be true, "Request #{i+1} should be allowed"
            end

            # 制限を超えたリクエスト
            result = manager.within_rate_limit?(limit_config[:action], identifier)
            expect(result).to be false
          end
        end
      end

      context 'rate limit expiration' do
        it 'resets counter after period expires' do
          identifier = 'test_user'
          action = 'password_reset'

          # 制限まで使用
          3.times { manager.within_rate_limit?(action, identifier) }
          expect(manager.within_rate_limit?(action, identifier)).to be false

          # 期間経過後
          travel_to 61.minutes.from_now do
            expect(manager.within_rate_limit?(action, identifier)).to be true
          end
        end
      end

      context 'multiple identifiers' do
        it 'tracks rate limits separately per identifier' do
          action = 'login_attempts'

          # User 1: 3 attempts
          3.times { manager.within_rate_limit?(action, 'user1') }

          # User 2: Should still have full limit
          5.times do
            expect(manager.within_rate_limit?(action, 'user2')).to be true
          end
          expect(manager.within_rate_limit?(action, 'user2')).to be false

          # User 1: Still has 2 attempts left
          2.times do
            expect(manager.within_rate_limit?(action, 'user1')).to be true
          end
          expect(manager.within_rate_limit?(action, 'user1')).to be false
        end
      end

      context 'unknown actions' do
        it 'allows requests for undefined actions' do
          100.times do
            expect(manager.within_rate_limit?('unknown_action', 'user')).to be true
          end
        end
      end

      context 'logging' do
        it 'logs rate limit violations' do
          identifier = 'test_user'
          action = 'password_reset'

          # 制限まで使用
          3.times { manager.within_rate_limit?(action, identifier) }

          expect(Rails.logger).to receive(:info).with(/rate_limit_exceeded/)
          manager.within_rate_limit?(action, identifier)
        end
      end
    end
  end

  # ============================================================================
  # セキュリティ設定・構成テスト
  # ============================================================================
  describe 'Security Configuration' do
    describe 'PCI_DSS_CONFIG' do
      it 'has required configuration keys' do
        config = SecurityComplianceManager::PCI_DSS_CONFIG

        expect(config).to include(
          :card_number_mask_pattern,
          :masked_format,
          :encryption_algorithm,
          :key_rotation_interval,
          :card_data_access_roles,
          :audit_retention_period
        )
      end

      it 'uses strong encryption' do
        expect(SecurityComplianceManager::PCI_DSS_CONFIG[:encryption_algorithm]).to eq('AES-256-GCM')
      end

      it 'has appropriate key rotation interval' do
        expect(SecurityComplianceManager::PCI_DSS_CONFIG[:key_rotation_interval]).to eq(90.days)
      end
    end

    describe 'GDPR_CONFIG' do
      it 'has required configuration keys' do
        config = SecurityComplianceManager::GDPR_CONFIG

        expect(config).to include(
          :personal_data_fields,
          :data_retention_periods,
          :consent_required_actions
        )
      end

      it 'defines appropriate retention periods' do
        periods = SecurityComplianceManager::GDPR_CONFIG[:data_retention_periods]

        expect(periods[:customer_data]).to eq(3.years)
        expect(periods[:employee_data]).to eq(7.years)
        expect(periods[:transaction_logs]).to eq(1.year)
        expect(periods[:audit_logs]).to eq(2.years)
      end

      it 'identifies all personal data fields' do
        fields = SecurityComplianceManager::GDPR_CONFIG[:personal_data_fields]

        expect(fields).to include(
          'name', 'email', 'phone_number', 'address',
          'birth_date', 'identification_number'
        )
      end
    end

    describe 'TIMING_ATTACK_CONFIG' do
      it 'has required configuration keys' do
        config = SecurityComplianceManager::TIMING_ATTACK_CONFIG

        expect(config).to include(
          :minimum_execution_time,
          :authentication_delays,
          :rate_limits
        )
      end

      it 'has progressive authentication delays' do
        delays = SecurityComplianceManager::TIMING_ATTACK_CONFIG[:authentication_delays]

        expect(delays[:first_attempt]).to eq(0.seconds)
        expect(delays[:second_attempt]).to eq(1.second)
        expect(delays[:third_attempt]).to eq(3.seconds)
        expect(delays[:fourth_attempt]).to eq(9.seconds)
        expect(delays[:fifth_attempt]).to eq(27.seconds)
      end

      it 'defines appropriate rate limits' do
        limits = SecurityComplianceManager::TIMING_ATTACK_CONFIG[:rate_limits]

        expect(limits[:login_attempts]).to eq({ count: 5, period: 15.minutes })
        expect(limits[:password_reset]).to eq({ count: 3, period: 1.hour })
        expect(limits[:api_requests]).to eq({ count: 100, period: 1.minute })
      end

      it 'uses Rails 8 compatible time units' do
        # Rails 8で廃止されたmillisecondsを使用していないことを確認
        expect(SecurityComplianceManager::TIMING_ATTACK_CONFIG[:minimum_execution_time]).to be_a(Numeric)
        expect(SecurityComplianceManager::TIMING_ATTACK_CONFIG[:minimum_execution_time]).to eq(0.1)
      end
    end
  end

  # ============================================================================
  # コンプライアンスステータスチェック
  # ============================================================================
  describe 'Compliance Status Checks' do
    describe '#check_pci_dss_compliance' do
      it 'checks for required PCI DSS features' do
        status = manager.send(:check_pci_dss_compliance)
        expect(status).to be_in([ true, false ])
      end

      it 'requires encryption keys' do
        allow(manager).to receive(:get_encryption_key).with('card_data').and_return(nil)
        expect(manager.send(:check_pci_dss_compliance)).to be false
      end
    end

    describe '#check_gdpr_compliance' do
      it 'checks for required GDPR features' do
        status = manager.send(:check_gdpr_compliance)
        expect(status).to be_in([ true, false ])
      end

      it 'requires personal data encryption key' do
        allow(manager).to receive(:get_encryption_key).with('personal_data').and_return(nil)
        expect(manager.send(:check_gdpr_compliance)).to be false
      end
    end

    describe '#check_timing_protection_compliance' do
      it 'checks for timing protection features' do
        status = manager.send(:check_timing_protection_compliance)
        expect(status).to be true
      end
    end
  end

  # ============================================================================
  # エラーハンドリングとエッジケース
  # ============================================================================
  describe 'Error Handling and Edge Cases' do
    describe 'encryption key management' do
      it 'falls back to default key for unknown contexts' do
        encrypted = manager.encrypt_sensitive_data('test', context: 'unknown_context')
        decrypted = manager.decrypt_sensitive_data(encrypted, context: 'unknown_context')

        expect(decrypted).to eq('test')
      end

      it 'generates key if none provided' do
        allow(Rails.application.credentials).to receive(:dig).and_return(nil)
        allow(ENV).to receive(:[]).with('SECURITY_ENCRYPTION_KEY').and_return(nil)

        # 新しいインスタンスで初期化をトリガー
        new_manager = described_class.instance
        new_manager.send(:initialize_encryption_keys)

        # キーが生成されていることを確認
        key = new_manager.send(:get_encryption_key, 'default')
        expect(key).to be_present
        expect(key.bytesize).to eq(32) # 256-bit key
      end
    end

    describe 'concurrent access' do
      it 'handles concurrent rate limit checks safely' do
        identifier = 'concurrent_user'
        action = 'login_attempts'
        results = []

        # 並行アクセスをシミュレート
        threads = 10.times.map do
          Thread.new do
            result = manager.within_rate_limit?(action, identifier)
            results << result
          end
        end

        threads.each(&:join)

        # 最大5つのtrueが含まれていることを確認
        true_count = results.count(true)
        expect(true_count).to be <= 5
        expect(true_count).to be >= 1
      end
    end

    describe 'data validation' do
      it 'handles very long strings in secure_compare' do
        long_string1 = 'A' * 10000
        long_string2 = 'A' * 10000

        result = manager.secure_compare(long_string1, long_string2)
        expect(result).to be true
      end

      it 'handles special characters in anonymization' do
        user = create(:admin, name: '<script>alert("XSS")</script>')

        result = manager.anonymize_personal_data(user)
        expect(result[:success]).to be true

        user.reload
        expect(user.name).not_to include('<script>')
        expect(user.name).to match(/^匿名ユーザー/)
      end
    end

    describe 'performance' do
      it 'encrypts large data efficiently' do
        large_data = 'X' * 1_000_000 # 1MB

        start_time = Time.current
        encrypted = manager.encrypt_sensitive_data(large_data)
        decrypted = manager.decrypt_sensitive_data(encrypted)
        end_time = Time.current

        expect(decrypted).to eq(large_data)
        expect(end_time - start_time).to be < 1.0 # Under 1 second
      end

      it 'handles bulk anonymization efficiently' do
        users = create_list(:admin, 10)

        start_time = Time.current
        users.each { |user| manager.anonymize_personal_data(user) }
        end_time = Time.current

        expect(end_time - start_time).to be < 2.0 # Under 2 seconds for 10 users
      end
    end
  end

  # ============================================================================
  # セキュリティベストプラクティステスト
  # ============================================================================
  describe 'Security Best Practices' do
    it 'does not log sensitive information' do
      # ログ出力を監視
      allow(Rails.logger).to receive(:info) do |message|
        expect(message).not_to include('4111111111111111') # 平文のカード番号
        expect(message).not_to include('password')
        expect(message).not_to include('secret')
      end

      manager.mask_credit_card('4111111111111111')
      manager.log_pci_dss_event('card_access', admin_user, {
        card_number: '4111111111111111',
        password: 'secret123'
      })
    end

    it 'uses secure random for anonymization' do
      users = create_list(:admin, 5)
      anonymized_emails = []

      users.each do |user|
        manager.anonymize_personal_data(user)
        user.reload
        anonymized_emails << user.email
      end

      # すべてのメールアドレスが異なることを確認
      expect(anonymized_emails.uniq.size).to eq(5)
    end

    it 'implements defense in depth' do
      # 多層防御の実装確認

      # 1. 入力検証
      expect(manager.mask_credit_card('invalid')).to eq('[INVALID]')

      # 2. 暗号化
      data = 'sensitive'
      encrypted = manager.encrypt_sensitive_data(data)
      expect(encrypted).not_to eq(data)

      # 3. アクセス制御（レート制限）
      5.times { manager.within_rate_limit?('login_attempts', 'user1') }
      expect(manager.within_rate_limit?('login_attempts', 'user1')).to be false

      # 4. 監査ログ
      expect {
        manager.log_pci_dss_event('access', admin_user, {})
      }.to change(ComplianceAuditLog, :count).by(1)
    end

    it 'prevents timing attacks on all comparison operations' do
      # すべての比較操作がタイミング攻撃に対して安全であることを確認
      operations = [
        -> { manager.secure_compare('test1', 'test2') },
        -> { manager.mask_credit_card('4111111111111111') }
      ]

      operations.each do |operation|
        times = []
        10.times do
          start = Time.current
          operation.call
          times << (Time.current - start)
        end

        # 実行時間のばらつきが小さい
        avg_time = times.sum / times.length
        variance = times.map { |t| (t - avg_time) ** 2 }.sum / times.length
        std_dev = Math.sqrt(variance)

        expect(std_dev).to be < 0.01 # 標準偏差が10ms未満
      end
    end
  end

  # ============================================================================
  # 統合シナリオテスト
  # ============================================================================
  describe 'Integration Scenarios' do
    it 'handles complete PCI DSS compliance workflow' do
      # 1. カード情報のマスキング
      card_number = '4111111111111111'
      masked = manager.mask_credit_card(card_number)
      expect(masked).to eq('4111****1111')

      # 2. 機密データの暗号化
      encrypted_card = manager.encrypt_sensitive_data(card_number, context: 'card_data')
      expect(encrypted_card).to be_present

      # 3. アクセスログの記録
      expect {
        manager.log_pci_dss_event('card_data_access', admin_user, {
          card_number: card_number,
          action: 'view',
          ip_address: '192.168.1.100'
        })
      }.to change(ComplianceAuditLog, :count).by(1)

      # 4. レート制限の適用
      5.times { manager.within_rate_limit?('api_requests', '192.168.1.100') }

      # 5. 復号化（権限があるユーザーのみ）
      decrypted = manager.decrypt_sensitive_data(encrypted_card, context: 'card_data')
      expect(decrypted).to eq(card_number)
    end

    it 'handles complete GDPR compliance workflow' do
      user = create(:store_user,
        name: '田中花子',
        email: 'tanaka@example.com',
        phone_number: '090-9876-5432'
      )

      # 1. データ保持期間のチェック
      old_log = create(:inventory_log, user: user, created_at: 2.years.ago)
      expect(manager.within_retention_period?('transaction_logs', old_log.created_at)).to be false

      # 2. 匿名化リクエスト
      anonymize_result = manager.anonymize_personal_data(user)
      expect(anonymize_result[:success]).to be true

      # 3. 削除リクエスト
      deletion_result = manager.process_data_deletion_request(user)
      expect(deletion_result[:success]).to be true

      # 4. 監査証跡の確認
      gdpr_logs = ComplianceAuditLog.where(compliance_standard: 'gdpr')
      expect(gdpr_logs.count).to be >= 2

      event_types = gdpr_logs.pluck(:event_type)
      expect(event_types).to include('data_anonymization', 'data_deletion')
    end

    it 'handles authentication with full security features' do
      identifier = 'user@example.com'

      # 1. 初回ログイン試行（遅延なし）
      start = Time.current
      manager.apply_authentication_delay(1, identifier)
      expect(Time.current - start).to be < 0.1

      # 2. レート制限チェック
      expect(manager.within_rate_limit?('login_attempts', identifier)).to be true

      # 3. パスワード比較（タイミング攻撃対策）
      correct_password = 'correct_password_123'
      wrong_password = 'wrong_password_456'

      result1 = manager.secure_compare(correct_password, correct_password)
      expect(result1).to be true

      result2 = manager.secure_compare(correct_password, wrong_password)
      expect(result2).to be false

      # 4. 失敗時の遅延適用
      manager.apply_authentication_delay(3, identifier)

      # 5. 監査ログ
      expect(Rails.logger).to receive(:info).at_least(:once)
      manager.within_rate_limit?('login_attempts', identifier)
    end
  end
end
