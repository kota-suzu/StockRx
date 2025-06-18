# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# ComplianceAuditLogsHelper テスト
# ============================================================================
# CLAUDE.md準拠: Phase 1 セキュリティ機能強化
# 
# 目的:
#   - コンプライアンス監査ログヘルパー機能のテスト
#   - 表示フォーマット機能の検証
#   - セキュリティ機能の正常性確認
#
# 設計思想:
#   - テスト駆動開発による品質確保
#   - 横展開: 他のヘルパーテストとの一貫性
#   - UI/UX品質の向上
# ============================================================================

RSpec.describe AdminControllers::ComplianceAuditLogsHelper, type: :helper do
  
  # ============================================================================
  # テストデータ
  # ============================================================================
  
  let(:admin_user) { create(:admin, :headquarters_admin, name: 'テスト管理者') }
  let(:store_user) { create(:store_user, name: 'テスト店舗ユーザー') }
  let(:compliance_log) { create(:compliance_audit_log, user: admin_user) }

  # ============================================================================
  # 表示フォーマット機能テスト
  # ============================================================================

  describe '#format_event_type' do
    it 'translates common event types to Japanese' do
      expect(helper.format_event_type('data_access')).to eq('データアクセス')
      expect(helper.format_event_type('login_attempt')).to eq('ログイン試行')
      expect(helper.format_event_type('data_breach')).to eq('データ漏洩')
      expect(helper.format_event_type('unauthorized_access')).to eq('不正アクセス')
    end

    it 'humanizes unknown event types' do
      expect(helper.format_event_type('unknown_event')).to eq('Unknown event')
      expect(helper.format_event_type('custom_action')).to eq('Custom action')
    end
  end

  describe '#format_compliance_standard' do
    it 'translates compliance standards to Japanese' do
      expect(helper.format_compliance_standard('PCI_DSS')).to eq('PCI DSS (クレジットカード情報保護)')
      expect(helper.format_compliance_standard('GDPR')).to eq('GDPR (EU一般データ保護規則)')
      expect(helper.format_compliance_standard('SOX')).to eq('SOX法 (サーベンス・オクスリー法)')
      expect(helper.format_compliance_standard('HIPAA')).to eq('HIPAA (医療保険の相互運用性と説明責任に関する法律)')
      expect(helper.format_compliance_standard('ISO27001')).to eq('ISO 27001 (情報セキュリティマネジメント)')
    end

    it 'returns original value for unknown standards' do
      expect(helper.format_compliance_standard('UNKNOWN')).to eq('UNKNOWN')
    end
  end

  describe '#severity_display_info' do
    it 'returns correct info for low severity' do
      info = helper.severity_display_info('low')
      expect(info[:label]).to eq('低')
      expect(info[:css_class]).to eq('badge bg-secondary')
      expect(info[:icon]).to eq('bi-info-circle')
      expect(info[:color]).to eq('text-secondary')
    end

    it 'returns correct info for critical severity' do
      info = helper.severity_display_info('critical')
      expect(info[:label]).to eq('緊急')
      expect(info[:css_class]).to eq('badge bg-dark')
      expect(info[:icon]).to eq('bi-shield-exclamation')
      expect(info[:color]).to eq('text-danger')
    end

    it 'returns medium info for unknown severity' do
      info = helper.severity_display_info('unknown')
      expect(info[:label]).to eq('中')
      expect(info[:css_class]).to eq('badge bg-warning text-dark')
    end
  end

  describe '#severity_badge' do
    it 'generates HTML badge for severity levels' do
      badge = helper.severity_badge('high')
      expect(badge).to include('badge bg-danger')
      expect(badge).to include('高')
    end

    it 'uses content_tag to generate proper HTML' do
      expect(helper).to receive(:content_tag).with(:span, '中', class: 'badge bg-warning text-dark')
      helper.severity_badge('medium')
    end
  end

  # ============================================================================
  # データ表示・マスキング機能テスト
  # ============================================================================

  describe '#safe_details_for_display' do
    let(:log_with_details) { create(:compliance_audit_log, :pci_dss) }

    it 'returns formatted details hash' do
      allow(log_with_details).to receive(:safe_details).and_return({
        'timestamp' => '2024-01-01T12:00:00Z',
        'action' => 'card_access',
        'result' => 'success'
      })

      result = helper.safe_details_for_display(log_with_details)
      
      expect(result).to include('タイムスタンプ')
      expect(result).to include('アクション')
      expect(result).to include('結果')
      expect(result['結果']).to eq('成功')
    end

    it 'handles nil log gracefully' do
      result = helper.safe_details_for_display(nil)
      expect(result).to eq({})
    end

    it 'handles errors gracefully' do
      allow(compliance_log).to receive(:safe_details).and_raise(StandardError.new('Test error'))
      
      result = helper.safe_details_for_display(compliance_log)
      expect(result['エラー']).to eq('詳細情報の取得に失敗しました')
    end
  end

  describe '#format_user_for_display' do
    context 'with Admin user' do
      it 'formats admin user with store info' do
        admin_with_store = create(:admin, :store_manager, name: 'テスト管理者')
        result = helper.format_user_for_display(admin_with_store)
        
        expect(result).to include('テスト管理者')
        expect(result).to include(admin_with_store.store.name)
        expect(result).to include('店舗管理者')
      end

      it 'formats headquarters admin' do
        hq_admin = create(:admin, :headquarters_admin, name: '本部管理者', store: nil)
        result = helper.format_user_for_display(hq_admin)
        
        expect(result).to include('本部管理者')
        expect(result).to include('(本部)')
        expect(result).to include('本部管理者')
      end
    end

    context 'with StoreUser' do
      it 'formats store user correctly' do
        result = helper.format_user_for_display(store_user)
        
        expect(result).to include('テスト店舗ユーザー')
        expect(result).to include(store_user.store.name)
        expect(result).to include('スタッフ') # デフォルトrole
      end
    end

    context 'with nil user' do
      it 'returns system indicator' do
        result = helper.format_user_for_display(nil)
        expect(result).to eq('システム')
      end
    end

    context 'with unknown user type' do
      let(:unknown_user) { double('UnknownUser') }

      it 'returns unknown user type message' do
        result = helper.format_user_for_display(unknown_user)
        expect(result).to eq('不明なユーザータイプ')
      end
    end
  end

  # ============================================================================
  # 時間・期間表示機能テスト
  # ============================================================================

  describe '#format_audit_datetime' do
    it 'formats datetime with relative time' do
      log = create(:compliance_audit_log, created_at: 2.hours.ago)
      result = helper.format_audit_datetime(log)
      
      expect(result).to include(log.created_at.strftime('%Y年%m月%d日 %H:%M:%S'))
      expect(result).to include('前')
    end

    it 'handles nil log gracefully' do
      result = helper.format_audit_datetime(nil)
      expect(result).to eq('不明')
    end

    it 'handles log without created_at' do
      log = double('Log', created_at: nil)
      result = helper.format_audit_datetime(log)
      expect(result).to eq('不明')
    end
  end

  describe '#format_retention_status' do
    it 'shows days remaining for active logs' do
      log = create(:compliance_audit_log, :pci_dss)
      result = helper.format_retention_status(log)
      
      expect(result).to include('まで')
      expect(result).to include('あと')
      expect(result).to include('日')
    end

    it 'shows expired status for old logs' do
      log = create(:compliance_audit_log, :expired_retention)
      result = helper.format_retention_status(log)
      
      # content_tagを使用した結果をテスト
      expect(result).to include('期限切れ')
      expect(result).to include('text-danger')
    end

    it 'handles nil log gracefully' do
      result = helper.format_retention_status(nil)
      expect(result).to eq('不明')
    end
  end

  # ============================================================================
  # レポート・分析支援機能テスト
  # ============================================================================

  describe '#compliance_summary_by_standard' do
    let!(:pci_high) { create(:compliance_audit_log, :pci_dss, severity: 'high') }
    let!(:pci_medium) { create(:compliance_audit_log, :pci_dss, severity: 'medium') }
    let!(:gdpr_low) { create(:compliance_audit_log, :gdpr, severity: 'low') }

    it 'groups logs by compliance standard and severity' do
      logs = ComplianceAuditLog.all
      summary = helper.compliance_summary_by_standard(logs)
      
      expect(summary['PCI_DSS'][:total]).to eq(2)
      expect(summary['PCI_DSS'][:by_severity]['high']).to eq(1)
      expect(summary['PCI_DSS'][:by_severity]['medium']).to eq(1)
      expect(summary['GDPR'][:total]).to eq(1)
      expect(summary['GDPR'][:by_severity]['low']).to eq(1)
    end
  end

  describe '#severity_statistics' do
    let!(:high_logs) { create_list(:compliance_audit_log, 3, severity: 'high') }
    let!(:medium_logs) { create_list(:compliance_audit_log, 2, severity: 'medium') }

    it 'calculates severity statistics with percentages' do
      logs = ComplianceAuditLog.all
      stats = helper.severity_statistics(logs)
      
      expect(stats['high'][:count]).to eq(3)
      expect(stats['high'][:percentage]).to eq(60.0)
      expect(stats['medium'][:count]).to eq(2)
      expect(stats['medium'][:percentage]).to eq(40.0)
    end

    it 'handles empty logs collection' do
      stats = helper.severity_statistics(ComplianceAuditLog.none)
      expect(stats).to eq({})
    end
  end

  describe '#activity_trend' do
    let!(:today_logs) { create_list(:compliance_audit_log, 2, created_at: Time.current) }
    let!(:yesterday_logs) { create_list(:compliance_audit_log, 3, created_at: 1.day.ago) }

    it 'returns daily activity trend' do
      logs = ComplianceAuditLog.all
      trend = helper.activity_trend(logs, :daily)
      
      expect(trend).to be_a(Hash)
      expect(trend.values.sum).to eq(5)
    end

    it 'returns weekly activity trend' do
      logs = ComplianceAuditLog.all
      trend = helper.activity_trend(logs, :weekly)
      
      expect(trend).to be_a(Hash)
    end

    it 'returns empty hash for unknown period' do
      logs = ComplianceAuditLog.all
      trend = helper.activity_trend(logs, :unknown)
      
      expect(trend).to eq({})
    end
  end

  # ============================================================================
  # 検索・フィルタリング支援テスト
  # ============================================================================

  describe '#format_search_conditions' do
    it 'formats compliance standard condition' do
      params = { compliance_standard: 'PCI_DSS' }
      conditions = helper.format_search_conditions(params)
      
      expect(conditions).to include('標準: PCI DSS (クレジットカード情報保護)')
    end

    it 'formats severity condition' do
      params = { severity: 'high' }
      conditions = helper.format_search_conditions(params)
      
      expect(conditions).to include('重要度: 高')
    end

    it 'formats event type condition' do
      params = { event_type: 'data_access' }
      conditions = helper.format_search_conditions(params)
      
      expect(conditions).to include('イベント: データアクセス')
    end

    it 'formats date range conditions' do
      params = { start_date: '2024-01-01', end_date: '2024-01-31' }
      conditions = helper.format_search_conditions(params)
      
      expect(conditions).to include('期間: 2024-01-01 〜 2024-01-31')
    end

    it 'formats start date only' do
      params = { start_date: '2024-01-01' }
      conditions = helper.format_search_conditions(params)
      
      expect(conditions).to include('開始日: 2024-01-01 以降')
    end

    it 'formats end date only' do
      params = { end_date: '2024-01-31' }
      conditions = helper.format_search_conditions(params)
      
      expect(conditions).to include('終了日: 2024-01-31 以前')
    end

    it 'returns default when no conditions' do
      params = {}
      conditions = helper.format_search_conditions(params)
      
      expect(conditions).to eq(['すべて'])
    end

    it 'combines multiple conditions' do
      params = {
        compliance_standard: 'GDPR',
        severity: 'critical',
        event_type: 'data_breach'
      }
      conditions = helper.format_search_conditions(params)
      
      expect(conditions.length).to eq(3)
      expect(conditions).to include('標準: GDPR (EU一般データ保護規則)')
      expect(conditions).to include('重要度: 緊急')
      expect(conditions).to include('イベント: データ漏洩')
    end
  end

  # ============================================================================
  # プライベートメソッドテスト（公開インターフェース経由）
  # ============================================================================

  describe 'private methods behavior' do
    describe 'through format_detail_value' do
      it 'formats timestamp values' do
        details = { 'timestamp' => '2024-01-01T12:00:00Z' }
        log = double('Log', safe_details: details)
        
        result = helper.safe_details_for_display(log)
        expect(result['タイムスタンプ']).to include('2024年01月01日')
      end

      it 'formats result values' do
        details = { 'result' => 'success' }
        log = double('Log', safe_details: details)
        
        result = helper.safe_details_for_display(log)
        expect(result['結果']).to eq('成功')
      end

      it 'formats legal basis values' do
        details = { 'legal_basis' => 'legitimate_interest' }
        log = double('Log', safe_details: details)
        
        result = helper.safe_details_for_display(log)
        expect(result['法的根拠']).to eq('正当な利益')
      end
    end
  end

  # ============================================================================
  # パフォーマンステスト
  # ============================================================================

  describe 'performance' do
    let!(:large_log_set) { create_list(:compliance_audit_log, 100) }

    it 'handles large datasets efficiently' do
      logs = ComplianceAuditLog.all
      
      expect {
        helper.compliance_summary_by_standard(logs)
        helper.severity_statistics(logs)
        helper.activity_trend(logs)
      }.to perform_under(0.5).sec
    end
  end

  # ============================================================================
  # エラーハンドリングテスト
  # ============================================================================

  describe 'error handling' do
    it 'handles malformed data gracefully' do
      malformed_log = double('Log', safe_details: nil)
      
      expect {
        helper.safe_details_for_display(malformed_log)
      }.not_to raise_error
    end

    it 'handles missing associations gracefully' do
      log_without_user = create(:compliance_audit_log, user: nil)
      
      expect {
        helper.format_user_for_display(log_without_user.user)
      }.not_to raise_error
    end
  end
end

# ============================================
# TODO: 🟡 Phase 3（重要）- ヘルパーテストの拡張
# ============================================
# 優先度: 中（品質向上）
#
# 【計画中の拡張テスト】
# 1. 🌐 国際化テスト
#    - 多言語対応のテスト
#    - ロケール切り替えテスト
#    - 地域固有フォーマットテスト
#
# 2. 🎨 UI/UXテスト
#    - HTMLアウトプット検証
#    - アクセシビリティテスト
#    - レスポンシブデザインテスト
#
# 3. 🔒 セキュリティテスト
#    - XSS防止テスト
#    - 機密情報マスキングテスト
#    - 入力サニタイゼーションテスト
#
# 4. 📊 統合テスト
#    - コントローラーとの統合テスト
#    - ビューレンダリングテスト
#    - エンドツーエンドテスト
# ============================================