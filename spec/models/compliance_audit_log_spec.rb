# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# ComplianceAuditLog モデルテスト
# ============================================================================
# CLAUDE.md準拠: Phase 1 セキュリティ機能強化
# 
# 目的:
#   - コンプライアンス監査ログ機能の包括的テスト
#   - PCI DSS、GDPR準拠機能の検証
#   - セキュリティ機能の正常性確認
#
# 設計思想:
#   - テスト駆動開発による品質確保
#   - 横展開: 他の監査ログテストとの一貫性
#   - カバレッジ向上によるバグ防止
# ============================================================================

RSpec.describe ComplianceAuditLog, type: :model do
  
  # ============================================================================
  # ファクトリとテストデータ
  # ============================================================================
  
  let(:admin_user) { create(:admin, :headquarters_admin) }
  let(:store_user) { create(:store_user) }
  let(:valid_attributes) do
    {
      event_type: 'data_access',
      user: admin_user,
      compliance_standard: 'PCI_DSS',
      severity: 'medium',
      encrypted_details: 'encrypted_test_data',
      immutable_hash: 'test_hash_value'
    }
  end

  # ============================================================================
  # バリデーションテスト
  # ============================================================================

  describe 'validations' do
    subject { described_class.new(valid_attributes) }

    it { should validate_presence_of(:event_type) }
    it { should validate_presence_of(:compliance_standard) }
    it { should validate_presence_of(:severity) }
    it { should validate_presence_of(:encrypted_details) }

    describe 'compliance_standard validation' do
      it 'accepts valid compliance standards' do
        %w[PCI_DSS GDPR SOX HIPAA ISO27001].each do |standard|
          subject.compliance_standard = standard
          expect(subject).to be_valid
        end
      end

      it 'rejects invalid compliance standards' do
        subject.compliance_standard = 'INVALID_STANDARD'
        expect(subject).not_to be_valid
        expect(subject.errors[:compliance_standard]).to include('は有効なコンプライアンス標準である必要があります')
      end
    end

    describe 'severity validation' do
      it 'accepts valid severity levels' do
        %w[low medium high critical].each do |severity|
          subject.severity = severity
          expect(subject).to be_valid
        end
      end

      it 'rejects invalid severity levels' do
        subject.severity = 'invalid_severity'
        expect(subject).not_to be_valid
        expect(subject.errors[:severity]).to include('は有効な重要度レベルである必要があります')
      end
    end
  end

  # ============================================================================
  # 関連付けテスト
  # ============================================================================

  describe 'associations' do
    it { should belong_to(:user).optional }

    describe 'polymorphic user association' do
      context 'with Admin user' do
        let(:log) { create(:compliance_audit_log, user: admin_user) }

        it 'associates with Admin correctly' do
          expect(log.user).to eq(admin_user)
          expect(log.user_type).to eq('Admin')
        end
      end

      context 'with StoreUser' do
        let(:log) { create(:compliance_audit_log, user: store_user) }

        it 'associates with StoreUser correctly' do
          expect(log.user).to eq(store_user)
          expect(log.user_type).to eq('StoreUser')
        end
      end

      context 'with system operation (no user)' do
        let(:log) { create(:compliance_audit_log, user: nil) }

        it 'allows nil user for system operations' do
          expect(log.user).to be_nil
          expect(log).to be_valid
        end
      end
    end
  end

  # ============================================================================
  # Enumテスト
  # ============================================================================

  describe 'enums' do
    describe 'compliance_standard' do
      it 'defines correct compliance standards' do
        expect(described_class.compliance_standards).to eq({
          'pci_dss' => 'PCI_DSS',
          'gdpr' => 'GDPR',
          'sox' => 'SOX',
          'hipaa' => 'HIPAA',
          'iso27001' => 'ISO27001'
        })
      end

      it 'provides convenience methods' do
        log = create(:compliance_audit_log, compliance_standard: 'PCI_DSS')
        expect(log.pci_dss?).to be true
        expect(log.gdpr?).to be false
      end
    end

    describe 'severity' do
      it 'defines correct severity levels' do
        expect(described_class.severities).to eq({
          'low' => 'low',
          'medium' => 'medium',
          'high' => 'high',
          'critical' => 'critical'
        })
      end

      it 'provides convenience methods' do
        log = create(:compliance_audit_log, severity: 'high')
        expect(log.high?).to be true
        expect(log.low?).to be false
      end
    end
  end

  # ============================================================================
  # スコープテスト
  # ============================================================================

  describe 'scopes' do
    let!(:pci_log) { create(:compliance_audit_log, compliance_standard: 'PCI_DSS', severity: 'high') }
    let!(:gdpr_log) { create(:compliance_audit_log, compliance_standard: 'GDPR', severity: 'medium') }
    let!(:critical_log) { create(:compliance_audit_log, severity: 'critical') }

    describe '.by_compliance_standard' do
      it 'filters by compliance standard' do
        results = described_class.by_compliance_standard('PCI_DSS')
        expect(results).to include(pci_log)
        expect(results).not_to include(gdpr_log)
      end
    end

    describe '.by_severity' do
      it 'filters by severity level' do
        results = described_class.by_severity('high')
        expect(results).to include(pci_log)
        expect(results).not_to include(gdpr_log)
      end
    end

    describe '.critical_events' do
      it 'returns high and critical severity logs' do
        results = described_class.critical_events
        expect(results).to include(pci_log, critical_log)
        expect(results).not_to include(gdpr_log)
      end
    end

    describe '.pci_dss_events' do
      it 'returns PCI DSS related logs' do
        results = described_class.pci_dss_events
        expect(results).to include(pci_log)
        expect(results).not_to include(gdpr_log)
      end
    end
  end

  # ============================================================================
  # セキュリティ機能テスト
  # ============================================================================

  describe 'security features' do
    let(:log) { create(:compliance_audit_log) }

    describe '#integrity_verified?' do
      it 'returns true for logs with valid hash' do
        # immutable_hashがset_immutable_hashコールバックで設定されることを想定
        expect(log.integrity_verified?).to be true
      end

      it 'returns false for logs with invalid hash' do
        log.update_column(:immutable_hash, 'invalid_hash')
        expect(log.integrity_verified?).to be false
      end
    end

    describe '#retention_expiry_date' do
      it 'calculates correct expiry for PCI DSS' do
        log.update!(compliance_standard: 'PCI_DSS')
        expected_date = log.created_at + 1.year
        expect(log.retention_expiry_date).to eq(expected_date)
      end

      it 'calculates correct expiry for GDPR' do
        log.update!(compliance_standard: 'GDPR')
        expected_date = log.created_at + 2.years
        expect(log.retention_expiry_date).to eq(expected_date)
      end

      it 'calculates correct expiry for SOX' do
        log.update!(compliance_standard: 'SOX')
        expected_date = log.created_at + 7.years
        expect(log.retention_expiry_date).to eq(expected_date)
      end
    end

    describe '#retention_expired?' do
      it 'returns false for recent logs' do
        expect(log.retention_expired?).to be false
      end

      it 'returns true for expired logs' do
        old_date = 2.years.ago
        log.update_column(:created_at, old_date)
        log.update!(compliance_standard: 'PCI_DSS')
        expect(log.retention_expired?).to be true
      end
    end
  end

  # ============================================================================
  # イミュータブル設計テスト
  # ============================================================================

  describe 'immutable design' do
    let(:log) { create(:compliance_audit_log) }

    describe 'update prevention' do
      it 'prevents modification of existing records' do
        expect { log.update!(event_type: 'modified_event') }.to raise_error(ActiveRecord::RecordInvalid)
        expect(log.errors[:base]).to include('監査ログは変更できません')
      end
    end

    describe 'deletion prevention' do
      it 'prevents deletion of records' do
        expect { log.destroy! }.to raise_error(ActiveRecord::RecordInvalid)
        expect(log.errors[:base]).to include('監査ログは削除できません')
      end
    end
  end

  # ============================================================================
  # クラスメソッドテスト
  # ============================================================================

  describe 'class methods' do
    describe '.log_security_event' do
      let(:details) { { ip_address: '192.168.1.1', action: 'card_access' } }

      it 'creates a compliance audit log with encrypted details' do
        expect {
          described_class.log_security_event(
            'card_data_access',
            admin_user,
            'PCI_DSS',
            'high',
            details
          )
        }.to change(described_class, :count).by(1)

        log = described_class.last
        expect(log.event_type).to eq('card_data_access')
        expect(log.user).to eq(admin_user)
        expect(log.compliance_standard).to eq('PCI_DSS')
        expect(log.severity).to eq('high')
        expect(log.encrypted_details).to be_present
      end

      it 'handles errors gracefully' do
        allow(SecurityComplianceManager.instance).to receive(:encrypt_sensitive_data).and_raise(StandardError.new('Encryption failed'))

        expect {
          described_class.log_security_event('test_event', admin_user, 'PCI_DSS', 'medium')
        }.to raise_error(StandardError, 'Encryption failed')
      end
    end

    describe '.generate_compliance_report' do
      let!(:pci_logs) do
        [
          create(:compliance_audit_log, compliance_standard: 'PCI_DSS', severity: 'high'),
          create(:compliance_audit_log, compliance_standard: 'PCI_DSS', severity: 'medium')
        ]
      end
      let!(:gdpr_log) { create(:compliance_audit_log, compliance_standard: 'GDPR') }

      it 'generates comprehensive compliance report' do
        start_date = 1.week.ago.to_date
        end_date = Date.current

        report = described_class.generate_compliance_report('PCI_DSS', start_date, end_date)

        expect(report[:compliance_standard]).to eq('PCI_DSS')
        expect(report[:summary][:total_events]).to eq(2)
        expect(report[:summary][:severity_breakdown]).to include('high' => 1, 'medium' => 1)
        expect(report[:critical_events]).to be_an(Array)
        expect(report[:integrity_status]).to include(:verified_logs, :compromised_logs)
        expect(report[:retention_status]).to include(:active_logs, :expired_logs)
      end
    end

    describe '.cleanup_expired_logs' do
      let!(:expired_log) do
        log = create(:compliance_audit_log, compliance_standard: 'PCI_DSS')
        log.update_column(:created_at, 2.years.ago)
        log
      end
      let!(:active_log) { create(:compliance_audit_log) }

      it 'identifies expired logs in dry run mode' do
        result = described_class.cleanup_expired_logs(dry_run: true)

        expect(result[:total_expired]).to eq(1)
        expect(result[:dry_run]).to be true
        expect(described_class.count).to eq(2) # No deletion in dry run
      end

      it 'deletes expired logs when dry_run is false' do
        result = described_class.cleanup_expired_logs(dry_run: false)

        expect(result[:deleted_count]).to eq(1)
        expect(described_class.count).to eq(1)
        expect(described_class.first).to eq(active_log)
      end
    end

    describe '.verify_integrity_batch' do
      let!(:valid_logs) { create_list(:compliance_audit_log, 3) }
      let!(:invalid_log) do
        log = create(:compliance_audit_log)
        log.update_column(:immutable_hash, 'invalid_hash')
        log
      end

      it 'verifies integrity of multiple logs' do
        result = described_class.verify_integrity_batch(limit: 10)

        expect(result[:total_checked]).to eq(4)
        expect(result[:verified_count]).to eq(3)
        expect(result[:compromised_count]).to eq(1)
        expect(result[:compromised_log_ids]).to include(invalid_log.id)
      end
    end
  end

  # ============================================================================
  # コールバックテスト
  # ============================================================================

  describe 'callbacks' do
    describe 'before_create :set_immutable_hash' do
      it 'sets immutable hash on creation' do
        log = build(:compliance_audit_log, immutable_hash: nil)
        log.save!

        expect(log.immutable_hash).to be_present
        expect(log.immutable_hash.length).to eq(64) # SHA-256 hash length
      end
    end
  end

  # ============================================================================
  # 例外処理・エラーハンドリングテスト
  # ============================================================================

  describe 'error handling' do
    context 'when SecurityComplianceManager is not available' do
      before do
        allow(SecurityComplianceManager).to receive(:instance).and_raise(StandardError.new('Manager unavailable'))
      end

      it 'handles missing SecurityComplianceManager gracefully' do
        expect {
          described_class.log_security_event('test_event', admin_user, 'PCI_DSS', 'medium')
        }.to raise_error(StandardError, 'Manager unavailable')
      end
    end
  end

  # ============================================================================
  # パフォーマンステスト
  # ============================================================================

  describe 'performance' do
    it 'creates logs efficiently' do
      expect {
        10.times { create(:compliance_audit_log) }
      }.to perform_under(1).sec
    end

    it 'queries with indexes efficiently' do
      create_list(:compliance_audit_log, 100)

      expect {
        described_class.by_compliance_standard('PCI_DSS').by_severity('high').count
      }.to perform_under(0.1).sec
    end
  end
end

# ============================================
# TODO: 🟡 Phase 3（重要）- テスト機能の拡張
# ============================================
# 優先度: 中（品質向上）
#
# 【計画中の拡張テスト】
# 1. 🔧 統合テスト
#    - SecurityComplianceManagerとの統合テスト
#    - 実際の暗号化・復号化テスト
#    - エンドツーエンドのコンプライアンステスト
#
# 2. 📊 パフォーマンステスト強化
#    - 大量データでの性能テスト
#    - メモリ使用量測定
#    - 並行処理テスト
#
# 3. 🔒 セキュリティテスト
#    - タイミング攻撃耐性テスト
#    - 暗号化強度テスト
#    - データ漏洩防止テスト
#
# 4. 🌐 多環境テスト
#    - 異なるデータベースでのテスト
#    - 設定違いでのテスト
#    - 負荷環境でのテスト
# ============================================