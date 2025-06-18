# frozen_string_literal: true

# ============================================================================
# ComplianceAuditLog - コンプライアンス監査ログモデル
# ============================================================================
# CLAUDE.md準拠: セキュリティ機能強化
#
# 目的:
#   - PCI DSS、GDPR等のコンプライアンス監査証跡管理
#   - セキュリティイベントの追跡と分析
#   - 法的要件に対応した監査ログ保存
#
# 設計思想:
#   - 改ざん防止機能（イミュータブル設計）
#   - 暗号化による機密情報保護
#   - 効率的な検索とレポート機能
# ============================================================================

class ComplianceAuditLog < ApplicationRecord
  # ============================================================================
  # アソシエーション
  # ============================================================================
  belongs_to :user, polymorphic: true, optional: true  # 実行ユーザー（admin/store_user、システム処理の場合はnil）

  # ============================================================================
  # バリデーション
  # ============================================================================
  # CLAUDE.md準拠: Rails enumは自動的にバリデーションを提供するため、
  #               手動のinclusionバリデーションは不要（競合回避）
  # メタ認知: enum使用時の二重バリデーション問題を解決
  # 横展開: 他のenum使用モデルでも同様の確認が必要
  validates :event_type, presence: true
  validates :compliance_standard, presence: true
  validates :severity, presence: true
  validates :encrypted_details, presence: true

  # ============================================================================
  # エニューム
  # ============================================================================
  # Rails 8対応: 位置引数でのenum定義（Rails 8.0の新構文）
  # メタ認知: enumキーと値の整合性確保、Rails 8の新しい構文に対応
  enum :compliance_standard, {
    pci_dss: "PCI_DSS",
    gdpr: "GDPR",
    sox: "SOX",
    hipaa: "HIPAA",
    iso27001: "ISO27001"
  }

  enum :severity, {
    low: "low",
    medium: "medium",
    high: "high",
    critical: "critical"
  }

  # ============================================================================
  # スコープ
  # ============================================================================
  scope :recent, -> { order(created_at: :desc) }
  scope :by_compliance_standard, ->(standard) { where(compliance_standard: standard) }
  scope :by_severity, ->(severity) { where(severity: severity) }
  scope :by_event_type, ->(event_type) { where(event_type: event_type) }
  scope :within_period, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :critical_events, -> { where(severity: [ :high, :critical ]) }  # enumキーに変更

  # 特定期間の重要イベント
  scope :compliance_violations, -> {
    where(event_type: [ "unauthorized_access", "data_breach", "compliance_violation" ])
  }

  # PCI DSS関連ログ
  scope :pci_dss_events, -> { by_compliance_standard(:pci_dss) }  # enumキーに変更

  # GDPR関連ログ
  scope :gdpr_events, -> { by_compliance_standard(:gdpr) }  # enumキーに変更

  # ============================================================================
  # コールバック
  # ============================================================================
  before_create :set_immutable_hash
  before_update :prevent_modification
  before_destroy :prevent_deletion

  # ============================================================================
  # インスタンスメソッド
  # ============================================================================

  # 暗号化された詳細情報を復号化して取得
  # @return [Hash] 復号化された詳細情報
  def decrypted_details
    return {} if encrypted_details.blank?

    begin
      security_manager = SecurityComplianceManager.instance
      decrypted_json = security_manager.decrypt_sensitive_data(
        encrypted_details,
        context: "audit_logs"
      )
      JSON.parse(decrypted_json)
    rescue => e
      Rails.logger.error "Failed to decrypt audit log details: #{e.message}"
      { error: "復号化に失敗しました" }
    end
  end

  # 読み取り専用の詳細情報（マスク済み）
  # @return [Hash] マスクされた詳細情報
  def safe_details
    details = decrypted_details
    return details if details.key?(:error)

    # 機密情報をマスク
    security_manager = SecurityComplianceManager.instance

    if details["card_number"]
      details["card_number"] = security_manager.mask_credit_card(details["card_number"])
    end

    # パスワード等の完全除去
    details.delete("password")
    details.delete("password_confirmation")
    details.delete("access_token")

    details
  end

  # ログの整合性確認
  # @return [Boolean] 整合性が保たれているかどうか
  def integrity_verified?
    return false if immutable_hash.blank?

    current_hash = calculate_integrity_hash
    secure_compare(immutable_hash, current_hash)
  end

  # コンプライアンス報告用サマリー
  # @return [Hash] レポート用のサマリー情報
  def compliance_summary
    {
      id: id,
      timestamp: created_at.iso8601,
      event_type: event_type,
      compliance_standard: compliance_standard,
      severity: severity,
      user_id: user_id,
      user_role: user&.role,
      verification_status: integrity_verified? ? "verified" : "compromised",
      retention_expires_at: retention_expiry_date
    }
  end

  # 保持期限日の計算
  # @return [Date] 保持期限日
  def retention_expiry_date
    # メタ認知: enumキーでの比較に変更
    case compliance_standard.to_sym
    when :pci_dss
      created_at + 1.year
    when :gdpr
      created_at + 2.years
    when :sox
      created_at + 7.years
    else
      created_at + 1.year
    end
  end

  # 保持期限切れかどうか
  # @return [Boolean] 保持期限切れかどうか
  def retention_expired?
    Date.current > retention_expiry_date
  end

  # ============================================================================
  # クラスメソッド
  # ============================================================================

  # セキュリティイベントの記録
  # @param event_type [String] イベントタイプ
  # @param user [User] 実行ユーザー
  # @param compliance_standard [String] コンプライアンス標準
  # @param severity [String] 重要度
  # @param details [Hash] 詳細情報
  # @return [ComplianceAuditLog] 作成された監査ログ
  def self.log_security_event(event_type, user, compliance_standard, severity, details = {})
    security_manager = SecurityComplianceManager.instance

    # 詳細情報を暗号化
    encrypted_details = security_manager.encrypt_sensitive_data(
      details.to_json,
      context: "audit_logs"
    )

    # 文字列値をenumキーに変換
    # CLAUDE.md準拠: メタ認知 - enumと文字列値の不整合解決
    # 横展開: 他のenum使用箇所でも同様の変換が必要
    standard_key = case compliance_standard
    when "PCI_DSS", :pci_dss then :pci_dss
    when "GDPR", :gdpr then :gdpr
    when "SOX", :sox then :sox
    when "HIPAA", :hipaa then :hipaa
    when "ISO27001", :iso27001 then :iso27001
    else
      Rails.logger.error "Invalid compliance standard: #{compliance_standard}"
      :pci_dss  # デフォルト値
    end

    severity_key = case severity.to_s
    when "low", :low then :low
    when "medium", :medium then :medium
    when "high", :high then :high
    when "critical", :critical then :critical
    else
      Rails.logger.error "Invalid severity: #{severity}"
      :low  # デフォルト値
    end

    create!(
      event_type: event_type,
      user: user,
      compliance_standard: standard_key,
      severity: severity_key,
      encrypted_details: encrypted_details
    )
  rescue => e
    Rails.logger.error "Failed to create compliance audit log: #{e.message}"
    raise
  end

  # コンプライアンスレポートの生成
  # @param compliance_standard [String/Symbol] コンプライアンス標準
  # @param start_date [Date] 開始日
  # @param end_date [Date] 終了日
  # @return [Hash] レポートデータ
  def self.generate_compliance_report(compliance_standard, start_date, end_date)
    logs = by_compliance_standard(compliance_standard)
           .within_period(start_date, end_date)
           .includes(:user)

    {
      compliance_standard: compliance_standard,
      report_period: {
        start_date: start_date.iso8601,
        end_date: end_date.iso8601
      },
      summary: {
        total_events: logs.count,
        severity_breakdown: logs.group(:severity).count,
        event_type_breakdown: logs.group(:event_type).count,
        daily_activity: logs.group_by_day(:created_at).count
      },
      critical_events: logs.critical_events.map(&:compliance_summary),
      integrity_status: {
        verified_logs: logs.select(&:integrity_verified?).count,
        compromised_logs: logs.reject(&:integrity_verified?).count
      },
      retention_status: {
        active_logs: logs.reject(&:retention_expired?).count,
        expired_logs: logs.select(&:retention_expired?).count
      }
    }
  end

  # 期限切れログのクリーンアップ
  # @param dry_run [Boolean] ドライランモードかどうか
  # @return [Hash] クリーンアップ結果
  def self.cleanup_expired_logs(dry_run: true)
    expired_logs = where("created_at < ?", 1.year.ago)

    result = {
      total_expired: expired_logs.count,
      by_compliance_standard: expired_logs.group(:compliance_standard).count,
      dry_run: dry_run
    }

    unless dry_run
      # 実際のクリーンアップ実行
      deleted_count = expired_logs.delete_all
      result[:deleted_count] = deleted_count

      Rails.logger.info "Cleaned up #{deleted_count} expired compliance audit logs"
    end

    result
  end

  # 整合性一括チェック
  # @param limit [Integer] チェック対象の最大件数
  # @return [Hash] チェック結果
  def self.verify_integrity_batch(limit: 1000)
    logs = recent.limit(limit)

    verified_count = 0
    compromised_logs = []

    logs.find_each do |log|
      if log.integrity_verified?
        verified_count += 1
      else
        compromised_logs << log.id
      end
    end

    {
      total_checked: logs.count,
      verified_count: verified_count,
      compromised_count: compromised_logs.count,
      compromised_log_ids: compromised_logs
    }
  end

  private

  # ============================================================================
  # プライベートメソッド
  # ============================================================================

  # 改ざん防止用ハッシュの設定
  def set_immutable_hash
    self.immutable_hash = calculate_integrity_hash
  end

  # 整合性ハッシュの計算
  # @return [String] SHA-256ハッシュ
  def calculate_integrity_hash
    hash_input = [
      event_type,
      user_id,
      compliance_standard,
      severity,
      encrypted_details,
      created_at&.to_f
    ].compact.join("|")

    Digest::SHA256.hexdigest(hash_input)
  end

  # 定数時間での文字列比較
  # @param str1 [String] 比較文字列1
  # @param str2 [String] 比較文字列2
  # @return [Boolean] 比較結果
  def secure_compare(str1, str2)
    SecurityComplianceManager.instance.secure_compare(str1, str2)
  end

  # レコード変更の防止
  def prevent_modification
    return if new_record?

    Rails.logger.warn "Attempt to modify immutable compliance audit log #{id}"
    errors.add(:base, "監査ログは変更できません")
    throw(:abort)  # Rails 8: 明示的な括弧
  end

  # レコード削除の防止
  def prevent_deletion
    Rails.logger.warn "Attempt to delete compliance audit log #{id}"
    errors.add(:base, "監査ログは削除できません")
    throw(:abort)  # Rails 8: 明示的な括弧
  end
end
