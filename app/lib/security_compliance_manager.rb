# frozen_string_literal: true

# ============================================================================
# SecurityComplianceManager - セキュリティコンプライアンス管理クラス
# ============================================================================
# CLAUDE.md準拠: Phase 1 セキュリティ機能強化
# 
# 目的:
#   - PCI DSS準拠のクレジットカード情報保護
#   - GDPR準拠の個人情報保護機能
#   - タイミング攻撃対策（定数時間アルゴリズム）
#
# 設計思想:
#   - セキュリティ・バイ・デザイン原則
#   - 防御の多層化
#   - 監査ログとコンプライアンス追跡
# ============================================================================

class SecurityComplianceManager
  include ActiveSupport::Configurable

  # ============================================================================
  # エラークラス
  # ============================================================================
  class SecurityViolationError < StandardError; end
  class ComplianceError < StandardError; end
  class EncryptionError < StandardError; end

  # ============================================================================
  # 設定定数
  # ============================================================================
  
  # PCI DSS準拠設定
  PCI_DSS_CONFIG = {
    # カード情報マスキング設定
    card_number_mask_pattern: /(\d{4})(\d{4,8})(\d{4})/,
    masked_format: '\1****\3',
    
    # 暗号化強度設定
    encryption_algorithm: 'AES-256-GCM',
    key_rotation_interval: 90.days,
    
    # アクセス制御
    card_data_access_roles: %w[headquarters_admin store_manager],
    audit_retention_period: 1.year
  }.freeze

  # GDPR準拠設定
  GDPR_CONFIG = {
    # 個人データ分類
    personal_data_fields: %w[
      name email phone_number address 
      birth_date identification_number
    ],
    
    # データ保持期間
    data_retention_periods: {
      customer_data: 3.years,
      employee_data: 7.years,
      transaction_logs: 1.year,
      audit_logs: 2.years
    },
    
    # 同意管理
    consent_required_actions: %w[
      marketing_emails data_analytics 
      third_party_sharing performance_cookies
    ]
  }.freeze

  # タイミング攻撃対策設定
  TIMING_ATTACK_CONFIG = {
    # 定数時間比較のための最小実行時間
    minimum_execution_time: 100.milliseconds,
    
    # 認証試行の遅延設定
    authentication_delays: {
      first_attempt: 0.seconds,
      second_attempt: 1.second,
      third_attempt: 3.seconds,
      fourth_attempt: 9.seconds,
      fifth_attempt: 27.seconds
    },
    
    # レート制限
    rate_limits: {
      login_attempts: { count: 5, period: 15.minutes },
      password_reset: { count: 3, period: 1.hour },
      api_requests: { count: 100, period: 1.minute }
    }
  }.freeze

  # ============================================================================
  # シングルトンパターン
  # ============================================================================
  include Singleton

  attr_reader :compliance_status, :last_audit_date

  def initialize
    @compliance_status = {
      pci_dss: false,
      gdpr: false,
      timing_protection: false
    }
    @last_audit_date = nil
    @encryption_keys = {}
    
    initialize_security_features
  end

  # ============================================================================
  # PCI DSS準拠機能
  # ============================================================================

  # クレジットカード番号のマスキング
  # @param card_number [String] クレジットカード番号
  # @return [String] マスクされたカード番号
  def mask_credit_card(card_number)
    return '[INVALID]' unless valid_credit_card_format?(card_number)
    
    # 定数時間処理（タイミング攻撃対策）
    secure_process_with_timing_protection do
      sanitized = card_number.gsub(/\D/, '')
      
      if sanitized.match?(PCI_DSS_CONFIG[:card_number_mask_pattern])
        sanitized.gsub(PCI_DSS_CONFIG[:card_number_mask_pattern], 
                      PCI_DSS_CONFIG[:masked_format])
      else
        '****'
      end
    end
  end

  # 機密データの暗号化
  # @param data [String] 暗号化するデータ
  # @param context [String] データコンテキスト（card_data, personal_data等）
  # @return [String] 暗号化されたデータ（Base64エンコード）
  def encrypt_sensitive_data(data, context: 'default')
    raise EncryptionError, "データが空です" if data.blank?
    
    begin
      cipher = OpenSSL::Cipher.new(PCI_DSS_CONFIG[:encryption_algorithm])
      cipher.encrypt
      
      # コンテキスト別の暗号化キー使用
      key = get_encryption_key(context)
      cipher.key = key
      
      iv = cipher.random_iv
      encrypted = cipher.update(data.to_s) + cipher.final
      
      # IV + 暗号化データ + 認証タグを結合
      combined = iv + encrypted + cipher.auth_tag
      Base64.strict_encode64(combined)
      
    rescue => e
      Rails.logger.error "Encryption failed: #{e.message}"
      raise EncryptionError, "暗号化に失敗しました"
    end
  end

  # 機密データの復号化
  # @param encrypted_data [String] 暗号化されたデータ（Base64エンコード）
  # @param context [String] データコンテキスト
  # @return [String] 復号化されたデータ
  def decrypt_sensitive_data(encrypted_data, context: 'default')
    raise EncryptionError, "暗号化データが空です" if encrypted_data.blank?
    
    begin
      combined = Base64.strict_decode64(encrypted_data)
      
      # IV（16バイト）、認証タグ（16バイト）、暗号化データを分離
      iv = combined[0..15]
      auth_tag = combined[-16..-1]
      encrypted = combined[16..-17]
      
      decipher = OpenSSL::Cipher.new(PCI_DSS_CONFIG[:encryption_algorithm])
      decipher.decrypt
      
      key = get_encryption_key(context)
      decipher.key = key
      decipher.iv = iv
      decipher.auth_tag = auth_tag
      
      decipher.update(encrypted) + decipher.final
      
    rescue => e
      Rails.logger.error "Decryption failed: #{e.message}"
      raise EncryptionError, "復号化に失敗しました"
    end
  end

  # PCI DSS監査ログ記録
  # @param action [String] 実行されたアクション
  # @param user [User] 実行ユーザー
  # @param details [Hash] 詳細情報
  def log_pci_dss_event(action, user, details = {})
    audit_entry = {
      timestamp: Time.current.iso8601,
      action: action,
      user_id: user&.id,
      user_role: user&.role,
      ip_address: details[:ip_address],
      user_agent: details[:user_agent],
      result: details[:result] || 'success',
      compliance_context: 'PCI_DSS',
      details: sanitize_audit_details(details)
    }
    
    # 暗号化して保存
    encrypted_entry = encrypt_sensitive_data(audit_entry.to_json, context: 'audit_logs')
    
    ComplianceAuditLog.create!(
      event_type: action,
      user: user,
      encrypted_details: encrypted_entry,
      compliance_standard: 'PCI_DSS',
      severity: determine_severity(action),
      created_at: Time.current
    )
    
    Rails.logger.info "[PCI_DSS_AUDIT] #{action} by #{user&.id} - #{details[:result]}"
  end

  # ============================================================================
  # GDPR準拠機能
  # ============================================================================

  # 個人データの匿名化
  # @param user [User] 対象ユーザー
  # @return [Hash] 匿名化結果
  def anonymize_personal_data(user)
    return { success: false, error: "ユーザーが見つかりません" } unless user
    
    begin
      anonymization_map = {}
      
      GDPR_CONFIG[:personal_data_fields].each do |field|
        if user.respond_to?(field) && user.send(field).present?
          original_value = user.send(field)
          anonymized_value = generate_anonymized_value(field, original_value)
          
          user.update_column(field, anonymized_value)
          anonymization_map[field] = {
            original_hash: Digest::SHA256.hexdigest(original_value.to_s),
            anonymized: anonymized_value
          }
        end
      end
      
      # 匿名化ログ記録
      log_gdpr_event('data_anonymization', user, {
        anonymized_fields: anonymization_map.keys,
        reason: 'user_request'
      })
      
      { success: true, anonymized_fields: anonymization_map.keys }
      
    rescue => e
      Rails.logger.error "Anonymization failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # データ保持期間チェック
  # @param data_type [String] データタイプ
  # @param created_at [DateTime] データ作成日時
  # @return [Boolean] 保持期間内かどうか
  def within_retention_period?(data_type, created_at)
    return true unless GDPR_CONFIG[:data_retention_periods].key?(data_type.to_sym)
    
    retention_period = GDPR_CONFIG[:data_retention_periods][data_type.to_sym]
    created_at > retention_period.ago
  end

  # データ削除要求処理
  # @param user [User] 対象ユーザー
  # @param request_type [String] 削除要求タイプ（right_to_erasure, data_retention_expired等）
  # @return [Hash] 削除結果
  def process_data_deletion_request(user, request_type: 'right_to_erasure')
    return { success: false, error: "ユーザーが見つかりません" } unless user
    
    begin
      deletion_summary = {
        user_id: user.id,
        request_type: request_type,
        deleted_records: [],
        anonymized_records: [],
        retained_records: []
      }
      
      # 関連データの削除・匿名化処理
      process_user_related_data(user, deletion_summary)
      
      # GDPR削除ログ記録
      log_gdpr_event('data_deletion', user, deletion_summary)
      
      { success: true, summary: deletion_summary }
      
    rescue => e
      Rails.logger.error "Data deletion failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # GDPR監査ログ記録
  # @param action [String] 実行されたアクション
  # @param user [User] 対象ユーザー
  # @param details [Hash] 詳細情報
  def log_gdpr_event(action, user, details = {})
    audit_entry = {
      timestamp: Time.current.iso8601,
      action: action,
      subject_user_id: user&.id,
      compliance_context: 'GDPR',
      legal_basis: details[:legal_basis] || 'legitimate_interest',
      details: sanitize_audit_details(details)
    }
    
    ComplianceAuditLog.create!(
      event_type: action,
      user: user,
      encrypted_details: encrypt_sensitive_data(audit_entry.to_json, context: 'audit_logs'),
      compliance_standard: 'GDPR',
      severity: determine_severity(action),
      created_at: Time.current
    )
  end

  # ============================================================================
  # タイミング攻撃対策
  # ============================================================================

  # 定数時間での文字列比較
  # @param str1 [String] 比較文字列1
  # @param str2 [String] 比較文字列2
  # @return [Boolean] 比較結果
  def secure_compare(str1, str2)
    secure_process_with_timing_protection do
      return false if str1.nil? || str2.nil?
      
      # 長さを同じにするためのパディング
      max_length = [str1.length, str2.length].max
      padded_str1 = str1.ljust(max_length, "\0")
      padded_str2 = str2.ljust(max_length, "\0")
      
      # 定数時間比較
      result = 0
      padded_str1.bytes.zip(padded_str2.bytes) do |a, b|
        result |= a ^ b
      end
      
      result == 0 && str1.length == str2.length
    end
  end

  # 認証試行時の遅延処理
  # @param attempt_count [Integer] 試行回数
  # @param identifier [String] 識別子（IPアドレス、ユーザーID等）
  def apply_authentication_delay(attempt_count, identifier)
    delay_config = TIMING_ATTACK_CONFIG[:authentication_delays]
    
    # 試行回数に基づく遅延時間決定
    delay_key = case attempt_count
    when 1 then :first_attempt
    when 2 then :second_attempt
    when 3 then :third_attempt
    when 4 then :fourth_attempt
    else :fifth_attempt
    end
    
    delay_time = delay_config[delay_key]
    
    if delay_time > 0
      Rails.logger.info "[TIMING_PROTECTION] Authentication delay applied: #{delay_time}s for #{identifier}"
      sleep(delay_time)
    end
    
    # 監査ログ記録
    log_timing_protection_event('authentication_delay', {
      attempt_count: attempt_count,
      delay_applied: delay_time,
      identifier: Digest::SHA256.hexdigest(identifier.to_s)
    })
  end

  # レート制限チェック
  # @param action [String] アクション名
  # @param identifier [String] 識別子
  # @return [Boolean] レート制限内かどうか
  def within_rate_limit?(action, identifier)
    return true unless TIMING_ATTACK_CONFIG[:rate_limits].key?(action.to_sym)
    
    limit_config = TIMING_ATTACK_CONFIG[:rate_limits][action.to_sym]
    cache_key = "rate_limit:#{action}:#{Digest::SHA256.hexdigest(identifier.to_s)}"
    
    current_count = Rails.cache.read(cache_key) || 0
    
    if current_count >= limit_config[:count]
      log_timing_protection_event('rate_limit_exceeded', {
        action: action,
        identifier_hash: Digest::SHA256.hexdigest(identifier.to_s),
        current_count: current_count,
        limit: limit_config[:count]
      })
      return false
    end
    
    # カウンターを増加
    Rails.cache.write(cache_key, current_count + 1, expires_in: limit_config[:period])
    true
  end

  private

  # ============================================================================
  # 初期化・設定メソッド
  # ============================================================================

  def initialize_security_features
    # 暗号化キーの初期化
    initialize_encryption_keys
    
    # コンプライアンス状態の確認
    check_compliance_status
    
    Rails.logger.info "[SECURITY] SecurityComplianceManager initialized"
  end

  def initialize_encryption_keys
    # 環境変数または Rails credentials から暗号化キーを取得
    default_key = Rails.application.credentials.dig(:security, :encryption_key) || 
                  ENV['SECURITY_ENCRYPTION_KEY'] || 
                  generate_encryption_key
    
    @encryption_keys = {
      'default' => default_key,
      'card_data' => Rails.application.credentials.dig(:security, :card_data_key) || default_key,
      'personal_data' => Rails.application.credentials.dig(:security, :personal_data_key) || default_key,
      'audit_logs' => Rails.application.credentials.dig(:security, :audit_logs_key) || default_key
    }
  end

  def generate_encryption_key
    OpenSSL::Random.random_bytes(32) # 256-bit key
  end

  def get_encryption_key(context)
    @encryption_keys[context] || @encryption_keys['default']
  end

  # ============================================================================
  # ユーティリティメソッド
  # ============================================================================

  def secure_process_with_timing_protection(&block)
    start_time = Time.current
    result = yield
    execution_time = Time.current - start_time
    
    # 最小実行時間を確保
    min_time = TIMING_ATTACK_CONFIG[:minimum_execution_time] / 1000.0
    if execution_time < min_time
      sleep(min_time - execution_time)
    end
    
    result
  end

  def valid_credit_card_format?(card_number)
    return false if card_number.blank?
    
    sanitized = card_number.gsub(/\D/, '')
    sanitized.length.between?(13, 19) && sanitized.match?(/^\d+$/)
  end

  def generate_anonymized_value(field, original_value)
    case field
    when 'email'
      "anonymized_#{SecureRandom.hex(8)}@example.com"
    when 'phone_number'
      "080-0000-#{rand(1000..9999)}"
    when 'name'
      "匿名ユーザー#{SecureRandom.hex(4)}"
    when 'address'
      "匿名化済み住所"
    else
      "anonymized_#{SecureRandom.hex(8)}"
    end
  end

  def process_user_related_data(user, deletion_summary)
    # Store関連データの処理
    if user.stores.any?
      deletion_summary[:retained_records] << "stores (business requirement)"
    end
    
    # InventoryLog関連データの処理
    user.inventory_logs.find_each do |log|
      if within_retention_period?('transaction_logs', log.created_at)
        # 個人情報のみ匿名化
        log.update!(
          admin_id: nil,
          description: log.description&.gsub(/#{user.name}/i, '匿名ユーザー')
        )
        deletion_summary[:anonymized_records] << "inventory_log_#{log.id}"
      else
        log.destroy!
        deletion_summary[:deleted_records] << "inventory_log_#{log.id}"
      end
    end
  end

  def sanitize_audit_details(details)
    sanitized = details.dup
    
    # 機密情報のマスキング
    if sanitized[:card_number]
      sanitized[:card_number] = mask_credit_card(sanitized[:card_number])
    end
    
    # パスワード等の除去
    sanitized.delete(:password)
    sanitized.delete(:password_confirmation)
    
    sanitized
  end

  def determine_severity(action)
    case action
    when 'data_deletion', 'data_anonymization', 'encryption_key_rotation'
      'high'
    when 'card_data_access', 'personal_data_export', 'authentication_delay'
      'medium'
    else
      'low'
    end
  end

  def log_timing_protection_event(action, details)
    Rails.logger.info "[TIMING_PROTECTION] #{action}: #{details.to_json}"
  end

  def check_compliance_status
    @compliance_status[:pci_dss] = check_pci_dss_compliance
    @compliance_status[:gdpr] = check_gdpr_compliance
    @compliance_status[:timing_protection] = check_timing_protection_compliance
    @last_audit_date = Time.current
  end

  def check_pci_dss_compliance
    # PCI DSS準拠チェックロジック
    required_features = [
      @encryption_keys['card_data'].present?,
      defined?(ComplianceAuditLog),
      PCI_DSS_CONFIG[:encryption_algorithm].present?
    ]
    
    required_features.all?
  end

  def check_gdpr_compliance
    # GDPR準拠チェックロジック
    required_features = [
      GDPR_CONFIG[:data_retention_periods].present?,
      @encryption_keys['personal_data'].present?,
      defined?(ComplianceAuditLog)
    ]
    
    required_features.all?
  end

  def check_timing_protection_compliance
    # タイミング攻撃対策チェックロジック
    TIMING_ATTACK_CONFIG[:minimum_execution_time] > 0 &&
    TIMING_ATTACK_CONFIG[:rate_limits].present?
  end
end

# ============================================
# TODO: 🟡 Phase 3（重要）- セキュリティ機能の拡張
# ============================================
# 優先度: 中（セキュリティ強化）
#
# 【計画中の拡張機能】
# 1. 🔐 高度な暗号化機能
#    - キーローテーション自動化
#    - HSM（Hardware Security Module）統合
#    - 複数環境対応（開発・ステージング・本番）
#
# 2. 📊 コンプライアンス監視
#    - リアルタイム監視ダッシュボード
#    - 自動コンプライアンスレポート
#    - 違反検知アラート
#
# 3. 🛡️ 高度な攻撃対策
#    - CSRF保護強化
#    - SQL injection検知
#    - XSS防御機能
#
# 4. 🔍 セキュリティ監査
#    - 定期的なセキュリティスキャン
#    - 脆弱性評価自動化
#    - ペネトレーションテスト支援
# ============================================