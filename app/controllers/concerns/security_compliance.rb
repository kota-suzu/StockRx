# frozen_string_literal: true

# ============================================================================
# SecurityCompliance - セキュリティコンプライアンス制御Concern
# ============================================================================
# CLAUDE.md準拠: セキュリティ機能強化
# 
# 目的:
#   - コントローラー横断でのセキュリティ制御統一
#   - PCI DSS、GDPR準拠機能の一元化
#   - タイミング攻撃対策の自動適用
#
# 設計思想:
#   - DRY原則に基づく共通機能集約
#   - 透明なセキュリティ強化
#   - 監査証跡の自動生成
# ============================================================================

module SecurityCompliance
  extend ActiveSupport::Concern

  included do
    # セキュリティ関連のbefore_action設定
    before_action :log_security_access
    before_action :apply_rate_limiting
    before_action :validate_security_headers
    
    # タイミング攻撃対策のafter_action
    after_action :apply_timing_protection
    
    # セキュリティマネージャーのインスタンス
    attr_reader :security_manager
  end

  # ============================================================================
  # クラスメソッド
  # ============================================================================
  class_methods do
    # PCI DSS保護が必要なアクションを指定
    # @param actions [Array<Symbol>] 保護対象アクション
    # @param options [Hash] オプション設定
    def protect_with_pci_dss(*actions, **options)
      before_action :enforce_pci_dss_protection, only: actions, **options
    end

    # GDPR保護が必要なアクションを指定
    # @param actions [Array<Symbol>] 保護対象アクション
    # @param options [Hash] オプション設定
    def protect_with_gdpr(*actions, **options)
      before_action :enforce_gdpr_protection, only: actions, **options
    end

    # 機密データアクセス時の監査ログ記録
    # @param actions [Array<Symbol>] 監査対象アクション
    # @param options [Hash] オプション設定
    def audit_sensitive_access(*actions, **options)
      around_action :audit_sensitive_data_access, only: actions, **options
    end
  end

  # ============================================================================
  # インスタンスメソッド
  # ============================================================================

  private

  # セキュリティマネージャーの初期化
  def initialize_security_manager
    @security_manager ||= SecurityComplianceManager.instance
  end

  # ============================================================================
  # before_action メソッド
  # ============================================================================

  # セキュリティアクセスログの記録
  def log_security_access
    initialize_security_manager
    
    # 基本的なアクセス情報を記録
    security_details = {
      controller: controller_name,
      action: action_name,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      referer: request.referer,
      request_method: request.method,
      timestamp: Time.current.iso8601
    }
    
    # 認証済みユーザーの場合は追加情報
    if current_user_for_security
      security_details.merge!(
        user_id: current_user_for_security.id,
        user_role: current_user_for_security.role,
        session_id: session.id
      )
    end
    
    # 管理者エリアアクセスの場合は高重要度でログ記録
    severity = controller_name.start_with?('admin_controllers') ? 'medium' : 'low'
    
    ComplianceAuditLog.log_security_event(
      'controller_access',
      current_user_for_security,
      'PCI_DSS',
      severity,
      security_details
    )
  end

  # レート制限の適用
  def apply_rate_limiting
    initialize_security_manager
    
    identifier = current_user_for_security&.id || request.remote_ip
    action_key = "#{controller_name}##{action_name}"
    
    unless @security_manager.within_rate_limit?(action_key, identifier)
      log_security_violation('rate_limit_exceeded', {
        action: action_key,
        identifier_type: current_user_for_security ? 'user' : 'ip'
      })
      
      render json: { 
        error: 'レート制限を超過しました。しばらく時間をおいてからもう一度お試しください。' 
      }, status: :too_many_requests
      return false
    end
  end

  # セキュリティヘッダーの検証
  def validate_security_headers
    # CSRF保護の確認
    unless request.get? || request.head? || verified_request?
      log_security_violation('csrf_token_mismatch', {
        expected_token: form_authenticity_token,
        provided_token: params[:authenticity_token] || request.headers['X-CSRF-Token']
      })
      
      respond_to do |format|
        format.html { redirect_to root_path, alert: 'セキュリティ検証に失敗しました。' }
        format.json { render json: { error: 'Invalid CSRF token' }, status: :forbidden }
      end
      return false
    end
  end

  # PCI DSS保護の実施
  def enforce_pci_dss_protection
    initialize_security_manager
    
    # クレジットカード情報を含む可能性のあるパラメータをチェック
    sensitive_params = detect_card_data_params
    
    if sensitive_params.any?
      # PCI DSS監査ログ記録
      @security_manager.log_pci_dss_event(
        'sensitive_data_access',
        current_user_for_security,
        {
          controller: controller_name,
          action: action_name,
          sensitive_params: sensitive_params.keys,
          ip_address: request.remote_ip,
          result: 'access_granted'
        }
      )
      
      # パラメータの暗号化（必要に応じて）
      encrypt_sensitive_params(sensitive_params)
    end
  end

  # GDPR保護の実施
  def enforce_gdpr_protection
    initialize_security_manager
    
    # 個人データアクセスの記録
    @security_manager.log_gdpr_event(
      'personal_data_access',
      current_user_for_security,
      {
        controller: controller_name,
        action: action_name,
        legal_basis: determine_legal_basis,
        data_subject: determine_data_subject,
        ip_address: request.remote_ip
      }
    )
    
    # GDPRオプトアウトユーザーのチェック
    if gdpr_opt_out_user?
      render json: { 
        error: 'GDPR規制により、このデータにアクセスできません。' 
      }, status: :forbidden
      return false
    end
  end

  # ============================================================================
  # after_action メソッド
  # ============================================================================

  # タイミング攻撃対策の適用
  def apply_timing_protection
    return unless response.status.in?([401, 403, 422])
    
    initialize_security_manager
    
    # 認証失敗時の遅延処理
    if response.status == 401
      apply_authentication_delay
    end
    
    # レスポンス時間の正規化
    normalize_response_timing
  end

  # ============================================================================
  # around_action メソッド
  # ============================================================================

  # 機密データアクセスの監査
  def audit_sensitive_data_access
    start_time = Time.current
    access_granted = false
    error_occurred = false
    
    begin
      yield
      access_granted = true
    rescue => e
      error_occurred = true
      Rails.logger.error "Sensitive data access error: #{e.message}"
      raise
    ensure
      end_time = Time.current
      duration = (end_time - start_time) * 1000 # ミリ秒
      
      # 詳細な監査ログ記録
      ComplianceAuditLog.log_security_event(
        'sensitive_data_access_complete',
        current_user_for_security,
        'PCI_DSS',
        error_occurred ? 'high' : 'medium',
        {
          controller: controller_name,
          action: action_name,
          duration_ms: duration.round(2),
          access_granted: access_granted,
          error_occurred: error_occurred,
          response_status: response.status,
          ip_address: request.remote_ip
        }
      )
    end
  end

  # ============================================================================
  # ヘルパーメソッド
  # ============================================================================

  # セキュリティ用の現在ユーザー取得
  def current_user_for_security
    current_admin || current_store_user || current_user
  end

  # カードデータパラメータの検出
  # @return [Hash] 機密パラメータのハッシュ
  def detect_card_data_params
    sensitive_patterns = {
      card_number: /card[_\-]?number|credit[_\-]?card|cc[_\-]?number/i,
      cvv: /cvv|cvc|security[_\-]?code/i,
      expiry: /expir|exp[_\-]?date|valid[_\-]?thru/i
    }
    
    detected = {}
    
    params.each do |key, value|
      next if value.blank?
      
      sensitive_patterns.each do |type, pattern|
        if key.match?(pattern) || value.to_s.match?(/^\d{13,19}$/)
          detected[key] = type
        end
      end
    end
    
    detected
  end

  # 機密パラメータの暗号化
  # @param sensitive_params [Hash] 機密パラメータ
  def encrypt_sensitive_params(sensitive_params)
    sensitive_params.each do |key, type|
      original_value = params[key]
      next if original_value.blank?
      
      # PCI DSS準拠の暗号化
      encrypted_value = @security_manager.encrypt_sensitive_data(
        original_value,
        context: 'card_data'
      )
      
      # パラメータを暗号化済みの値に置換
      params[key] = encrypted_value
      
      # リクエストログから元の値を除外
      request.filtered_parameters[key] = '[ENCRYPTED]'
    end
  end

  # GDPR法的根拠の決定
  # @return [String] 法的根拠
  def determine_legal_basis
    case controller_name
    when /admin/
      'legitimate_interest'
    when /store/
      'contract_performance'
    else
      'consent'
    end
  end

  # データ主体の決定
  # @return [Hash] データ主体情報
  def determine_data_subject
    if params[:user_id]
      { type: 'user', id: params[:user_id] }
    elsif params[:id] && controller_name.include?('user')
      { type: 'user', id: params[:id] }
    else
      { type: 'unknown' }
    end
  end

  # GDPRオプトアウトユーザーかどうか
  # @return [Boolean] オプトアウト状態
  def gdpr_opt_out_user?
    # TODO: ユーザーのGDPR設定確認ロジック実装
    false
  end

  # 認証遅延の適用
  def apply_authentication_delay
    session[:auth_attempts] = (session[:auth_attempts] || 0) + 1
    identifier = current_user_for_security&.id || request.remote_ip
    
    @security_manager.apply_authentication_delay(
      session[:auth_attempts],
      identifier
    )
  end

  # レスポンス時間の正規化
  def normalize_response_timing
    # レスポンス時間を一定に保つための処理
    # タイミング攻撃を防ぐため
    start_time = @_action_start_time || Time.current
    elapsed = Time.current - start_time
    
    # 最小レスポンス時間を確保
    min_time = 0.1 # 100ms
    if elapsed < min_time
      sleep(min_time - elapsed)
    end
  end

  # セキュリティ違反のログ記録
  # @param violation_type [String] 違反タイプ
  # @param details [Hash] 詳細情報
  def log_security_violation(violation_type, details = {})
    ComplianceAuditLog.log_security_event(
      violation_type,
      current_user_for_security,
      'PCI_DSS',
      'high',
      details.merge(
        controller: controller_name,
        action: action_name,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    )
  end
end