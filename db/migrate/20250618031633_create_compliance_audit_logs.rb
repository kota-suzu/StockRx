class CreateComplianceAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :compliance_audit_logs do |t|
      t.string :event_type, null: false, comment: "イベントタイプ（data_access, login_attempt等）"
      t.references :user, null: true, polymorphic: true, comment: "実行ユーザー（admin/store_user、システム処理の場合はnull）"
      t.string :compliance_standard, null: false, comment: "コンプライアンス標準（PCI_DSS, GDPR等）"
      t.string :severity, null: false, comment: "重要度レベル（low, medium, high, critical）"
      t.text :encrypted_details, null: false, comment: "暗号化された詳細情報"
      t.string :immutable_hash, null: false, comment: "改ざん防止用ハッシュ値"

      t.timestamps
    end

    # パフォーマンス最適化用インデックス
    add_index :compliance_audit_logs, :event_type, name: "index_compliance_audit_logs_on_event_type"
    add_index :compliance_audit_logs, :compliance_standard, name: "index_compliance_audit_logs_on_compliance_standard"
    add_index :compliance_audit_logs, :severity, name: "index_compliance_audit_logs_on_severity"
    add_index :compliance_audit_logs, :created_at, name: "index_compliance_audit_logs_on_created_at"
    add_index :compliance_audit_logs, [ :compliance_standard, :severity ], name: "index_compliance_audit_logs_on_standard_severity"
    add_index :compliance_audit_logs, [ :event_type, :created_at ], name: "index_compliance_audit_logs_on_event_type_created_at"

    # 重要イベント用の複合インデックス
    add_index :compliance_audit_logs, [ :severity, :compliance_standard, :created_at ],
              where: "severity IN ('high', 'critical')",
              name: "index_compliance_audit_logs_critical_events"
  end
end
