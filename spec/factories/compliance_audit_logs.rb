# frozen_string_literal: true

# ============================================================================
# ComplianceAuditLog FactoryBot定義
# ============================================================================
# CLAUDE.md準拠: Phase 1 セキュリティ機能強化
#
# 目的:
#   - テスト用ComplianceAuditLogデータの生成
#   - 様々なシナリオに対応したファクトリ
#   - 他のファクトリとの一貫性確保
#
# 設計思想:
#   - リアルなテストデータの生成
#   - 横展開: 他の監査ログファクトリとの一貫性
#   - テストの可読性と保守性向上
# ============================================================================

FactoryBot.define do
  factory :compliance_audit_log do
    # ============================================================================
    # 基本属性
    # ============================================================================

    event_type { 'data_access' }
    compliance_standard { 'PCI_DSS' }
    severity { 'medium' }

    # 暗号化された詳細情報（テスト用）
    encrypted_details do
      # テスト環境では実際の暗号化の代わりにBase64エンコードを使用
      sample_details = {
        timestamp: Time.current.iso8601,
        action: 'test_action',
        ip_address: Faker::Internet.ip_v4_address,
        user_agent: Faker::Internet.user_agent,
        result: 'success'
      }
      Base64.strict_encode64(sample_details.to_json)
    end

    # 改ざん防止用ハッシュ（テスト用）
    immutable_hash { Digest::SHA256.hexdigest("test_hash_#{SecureRandom.hex(16)}") }

    # ============================================================================
    # 関連付け
    # ============================================================================

    # ポリモーフィック関連: デフォルトでAdminユーザー
    association :user, factory: :admin

    # ============================================================================
    # トレイト定義
    # ============================================================================

    # コンプライアンス標準別
    trait :pci_dss do
      compliance_standard { 'PCI_DSS' }
      event_type { 'card_data_access' }

      encrypted_details do
        details = {
          action: 'credit_card_processing',
          masked_card_number: '****-****-****-1234',
          transaction_amount: Faker::Commerce.price(range: 100..1000),
          merchant_id: Faker::Alphanumeric.alphanumeric(number: 8)
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    trait :gdpr do
      compliance_standard { 'GDPR' }
      event_type { 'personal_data_access' }

      encrypted_details do
        details = {
          action: 'personal_data_export',
          data_subject_id: Faker::Number.number(digits: 6),
          data_categories: [ 'name', 'email', 'address' ],
          legal_basis: 'legitimate_interest'
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    trait :sox do
      compliance_standard { 'SOX' }
      event_type { 'financial_data_access' }

      encrypted_details do
        details = {
          action: 'financial_report_generation',
          report_type: 'quarterly_earnings',
          fiscal_period: '2024-Q1',
          approval_required: true
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    trait :hipaa do
      compliance_standard { 'HIPAA' }
      event_type { 'health_data_access' }

      encrypted_details do
        details = {
          action: 'patient_record_access',
          patient_id: Faker::Alphanumeric.alphanumeric(number: 10),
          record_type: 'prescription_history',
          access_reason: 'treatment_consultation'
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    trait :iso27001 do
      compliance_standard { 'ISO27001' }
      event_type { 'security_event' }

      encrypted_details do
        details = {
          action: 'security_policy_update',
          policy_id: Faker::Alphanumeric.alphanumeric(number: 6),
          change_type: 'access_control_modification',
          reviewer_id: Faker::Number.number(digits: 4)
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    # 重要度レベル別
    trait :low_severity do
      severity { 'low' }
      event_type { 'routine_access' }
    end

    trait :medium_severity do
      severity { 'medium' }
      event_type { 'data_export' }
    end

    trait :high_severity do
      severity { 'high' }
      event_type { 'unauthorized_access_attempt' }
    end

    trait :critical_severity do
      severity { 'critical' }
      event_type { 'data_breach' }

      encrypted_details do
        details = {
          action: 'security_incident',
          incident_type: 'data_breach',
          affected_records: Faker::Number.between(from: 100, to: 10000),
          containment_status: 'in_progress',
          notification_required: true
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    # ユーザータイプ別
    trait :admin_user do
      association :user, factory: :admin
    end

    trait :store_user do
      association :user, factory: :store_user
    end

    trait :headquarters_admin do
      association :user, factory: [ :admin, :headquarters_admin ]
    end

    trait :store_manager do
      association :user, factory: [ :admin, :store_manager ]
    end

    trait :system_operation do
      user { nil }
      event_type { 'system_maintenance' }

      encrypted_details do
        details = {
          action: 'automated_cleanup',
          system_component: 'log_rotation',
          affected_tables: [ 'audit_logs', 'inventory_logs' ],
          execution_time: Time.current.iso8601
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    # セキュリティイベント別
    trait :login_attempt do
      event_type { 'login_attempt' }
      severity { 'medium' }

      encrypted_details do
        details = {
          action: 'authentication_attempt',
          ip_address: Faker::Internet.ip_v4_address,
          user_agent: Faker::Internet.user_agent,
          result: %w[success failure].sample,
          attempt_count: Faker::Number.between(from: 1, to: 5)
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    trait :data_breach_event do
      event_type { 'data_breach' }
      severity { 'critical' }
      compliance_standard { 'GDPR' }

      encrypted_details do
        details = {
          action: 'security_incident',
          incident_id: Faker::Alphanumeric.alphanumeric(number: 12),
          breach_type: 'unauthorized_access',
          affected_data_types: [ 'email', 'name', 'phone' ],
          discovered_at: Time.current.iso8601,
          reported_to_authority: false
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    trait :compliance_violation do
      event_type { 'compliance_violation' }
      severity { 'high' }

      encrypted_details do
        details = {
          action: 'policy_violation',
          violation_type: 'data_retention_exceeded',
          policy_id: Faker::Alphanumeric.alphanumeric(number: 8),
          remediation_required: true,
          deadline: 30.days.from_now.iso8601
        }
        Base64.strict_encode64(details.to_json)
      end
    end

    # 時間軸関連
    trait :recent do
      created_at { 1.hour.ago }
    end

    trait :yesterday do
      created_at { 1.day.ago }
    end

    trait :last_week do
      created_at { 1.week.ago }
    end

    trait :last_month do
      created_at { 1.month.ago }
    end

    trait :expired_retention do
      created_at { 2.years.ago }
      compliance_standard { 'PCI_DSS' } # 1年保持期間なので期限切れ
    end

    # 整合性関連
    trait :compromised_integrity do
      after(:create) do |log|
        # 作成後にハッシュを改ざんして整合性を破る
        log.update_column(:immutable_hash, 'compromised_hash')
      end
    end

    trait :valid_integrity do
      # デフォルトで整合性は保たれる（set_immutable_hashコールバックによる）
    end

    # ============================================================================
    # 複合トレイト
    # ============================================================================

    # PCI DSS重要イベント
    trait :pci_critical_event do
      pci_dss
      critical_severity
      headquarters_admin
    end

    # GDPR個人データ処理
    trait :gdpr_personal_data_processing do
      gdpr
      medium_severity
      store_manager

      event_type { 'personal_data_processing' }
    end

    # システム管理イベント
    trait :system_admin_event do
      system_operation
      low_severity

      compliance_standard { :iso27001 }  # enum\u30ad\u30fc\u306b\u5909\u63db
      event_type { 'system_configuration_change' }
    end

    # セキュリティインシデント
    trait :security_incident do
      critical_severity
      headquarters_admin

      event_type { 'security_incident' }
      compliance_standard { [ :pci_dss, :gdpr, :iso27001 ].sample }  # enum\u30ad\u30fc\u306b\u5909\u63db
    end
  end
end

# ============================================
# TODO: 🟡 Phase 3（重要）- ファクトリの拡張
# ============================================
# 優先度: 中（テスト品質向上）
#
# 【計画中の拡張ファクトリ】
# 1. 🌍 国際化対応
#    - 多言語でのイベントタイプ
#    - 地域別コンプライアンス要件
#    - タイムゾーン考慮
#
# 2. 📊 統計・分析用
#    - 大量データ生成用ファクトリ
#    - トレンド分析用時系列データ
#    - パフォーマンステスト用データセット
#
# 3. 🔧 特殊ケース対応
#    - エラー状態のファクトリ
#    - 境界値テスト用データ
#    - 例外ケース用ファクトリ
#
# 4. 🔗 統合テスト用
#    - 複数システム連携用ファクトリ
#    - ワークフロー全体テスト用
#    - エンドツーエンドテスト用
# ============================================
