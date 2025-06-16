# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # エラーハンドリングの追加
  include ErrorHandlers
  
  # セキュリティヘッダーの追加 (Phase 5-3)
  include SecurityHeaders

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # リクエストごとにCurrentを設定
  before_action :set_current_attributes

  # ============================================
  # セキュリティ監視の統合
  # ============================================

  before_action :monitor_request_security
  after_action :track_response_metrics

  # TODO: 🔴 Phase 1（緊急）- パフォーマンス監視機能
  # 優先度: 高（CLAUDE.md準拠）
  # 実装内容:
  #   - SQLクエリ数監視（Bullet gem統合拡張）
  #   - メモリ使用量監視システム
  #   - レスポンス時間ベンチマーク
  # around_action :monitor_performance, if: -> { Rails.env.development? }

  # 管理画面用ヘルパーはすべて「app/helpers」直下に配置し
  # Railsの規約に従ってモジュール名と一致させる
  # これによりZeitwerkのロード問題を解決
  # helper_method :some_method が必要であれば、ここに追加する

  private

  # Currentにリクエスト情報とユーザー情報を設定
  def set_current_attributes
    Current.reset
    Current.set_request_info(request)
    # ログイン機能実装後に有効化
    # Current.user = current_user if respond_to?(:current_user) && current_user
  end

  # セキュリティ監視機能
  def monitor_request_security
    # テスト環境では無効化
    return if Rails.env.test?

    # TODO: 🔴 Phase 1 - テスト環境でのセキュリティチェック完全無効化（優先度：最高）
    # 問題: Rails.env.test?の判定が効かず、テストで403エラーが発生
    # 原因: 環境変数やRailsの設定でテスト環境が正しく判定されていない可能性
    # 影響: request specが全体的に失敗
    # 解決策:
    # 1. config/environments/test.rb でセキュリティ機能を無効化
    # 2. SecurityMonitorクラスにテストモードを追加
    # 3. before(:each) でSecurityMonitorを明示的に無効化

    # IP ブロックチェック
    if SecurityMonitor.is_blocked?(request.remote_ip)
      Rails.logger.warn "Blocked IP attempted access: #{request.remote_ip}"
      render plain: "Access Denied", status: :forbidden
      return
    end

    # リクエスト分析
    suspicious_patterns = SecurityMonitor.analyze_request(request)

    # 疑わしいパターンが検出された場合のログ記録
    if suspicious_patterns.any?
      Rails.logger.warn({
        event: "suspicious_request_detected",
        patterns: suspicious_patterns,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        path: request.path,
        method: request.request_method
      }.to_json)
    end
  end

  # レスポンスメトリクスの追跡
  def track_response_metrics
    # テスト環境では無効化
    return if Rails.env.test?

    # レスポンス時間が異常に長い場合の検出
    if defined?(@request_start_time)
      response_time = Time.current - @request_start_time

      if response_time > SecurityMonitor::SUSPICIOUS_THRESHOLDS[:response_time]
        Rails.logger.warn({
          event: "slow_response_detected",
          response_time_seconds: response_time,
          ip_address: request.remote_ip,
          path: request.path,
          method: request.request_method
        }.to_json)
      end
    end
  end
end

# ============================================
# TODO: ApplicationController セキュリティ強化
# Phase 1（優先度：高、推定：2-3日）
# 関連: doc/remaining_tasks.md - セキュリティ強化
# ============================================
# 1. 認証・認可の段階的強化（Phase 1）
#    - JWT トークンベース認証への移行
#    - ロールベースアクセス制御（RBAC）の実装
#    - 多要素認証（MFA）の統合
#
# def require_mfa_for_sensitive_operations
#   return unless defined?(Current.admin) && Current.admin
#
#   sensitive_actions = %w[destroy bulk_delete export_data]
#   sensitive_controllers = %w[admins inventories]
#
#   if sensitive_controllers.include?(controller_name) &&
#      sensitive_actions.include?(action_name)
#
#     unless mfa_verified_recently?
#       redirect_to mfa_verification_path
#       return false
#     end
#   end
# end
#
# 2. セッション管理の強化（Phase 1）
#    - セッション固定攻撃対策
#    - 同時ログイン制限
#    - セッションタイムアウト管理
#
# def enforce_session_security
#   # セッション固定攻撃対策
#   reset_session if session_fixation_detected?
#
#   # 異なるIPからのアクセス検出
#   if session[:original_ip] && session[:original_ip] != request.remote_ip
#     Rails.logger.warn "Session IP mismatch detected"
#     reset_session
#     redirect_to new_admin_session_path
#     return false
#   end
#
#   # セッション有効期限チェック
#   if session[:expires_at] && Time.current > session[:expires_at]
#     expire_session
#     return false
#   end
# end
#
# 3. CSRF保護の強化（Phase 1）
#    - SameSite Cookie の適用
#    - Origin ヘッダー検証
#    - Referer ヘッダー検証
#
# def enhanced_csrf_protection
#   # Origin ヘッダー検証
#   if request.post? || request.patch? || request.put? || request.delete?
#     origin = request.headers['Origin']
#     referer = request.headers['Referer']
#
#     unless valid_origin?(origin) || valid_referer?(referer)
#       Rails.logger.warn "Invalid origin/referer detected"
#       head :forbidden
#       return false
#     end
#   end
# end
#
# 4. レート制限の実装（Phase 2）
#    - IP ベースレート制限
#    - ユーザーベースレート制限
#    - エンドポイント別制限
#
# def enforce_rate_limits
#   limits = {
#     login: { limit: 5, period: 15.minutes },
#     api: { limit: 100, period: 1.hour },
#     file_upload: { limit: 10, period: 1.hour }
#   }
#
#   limit_key = determine_rate_limit_key
#   limit_config = limits[limit_key]
#
#   if limit_config && rate_limit_exceeded?(limit_key, limit_config)
#     render json: { error: "Rate limit exceeded" }, status: :too_many_requests
#     return false
#   end
# end
#
# 5. Content Security Policy の実装（Phase 2）
#    - XSS 攻撃対策の強化
#    - インライン JavaScript/CSS の制限
#    - 外部リソース読み込み制限
#
# def set_security_headers
#   response.headers['X-Frame-Options'] = 'DENY'
#   response.headers['X-Content-Type-Options'] = 'nosniff'
#   response.headers['X-XSS-Protection'] = '1; mode=block'
#   response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
#
#   # Content Security Policy
#   csp_directives = [
#     "default-src 'self'",
#     "script-src 'self' 'unsafe-inline'",  # TODO Phase 3: unsafe-inline を削除
#     "style-src 'self' 'unsafe-inline'",
#     "img-src 'self' data: https:",
#     "font-src 'self'",
#     "connect-src 'self' ws: wss:",
#     "object-src 'none'",
#     "base-uri 'self'"
#   ]
#
#   response.headers['Content-Security-Policy'] = csp_directives.join('; ')
# end
#
# 6. 監査ログの統合（Phase 1）
#    - 全ての重要なアクションの記録
#    - 構造化ログの出力
#    - 異常パターンの自動検出
#
# def log_user_action
#   return unless should_log_action?
#
#   AuditLog.create!(
#     auditable: determine_auditable_object,
#     action: "#{controller_name}##{action_name}",
#     message: generate_action_message,
#     details: {
#       ip_address: request.remote_ip,
#       user_agent: request.user_agent,
#       referer: request.referer,
#       params: filtered_params
#     },
#     user_id: current_admin&.id,
#     operation_source: 'web'
#   )
# end
#
# 7. 例外処理の統合（Phase 2）
#    - セキュリティ関連エラーの適切な処理
#    - 情報漏洩の防止
#    - インシデント対応の自動化
#
# rescue_from SecurityError, with: :handle_security_error
# rescue_from ActionController::InvalidAuthenticityToken, with: :handle_csrf_error
# rescue_from ActionController::ParameterMissing, with: :handle_parameter_error
#
# def handle_security_error(exception)
#   Rails.logger.error({
#     event: "security_error",
#     error_class: exception.class.name,
#     error_message: exception.message,
#     ip_address: request.remote_ip,
#     path: request.path
#   }.to_json)
#
#   # セキュリティチームへの通知
#   SecurityMonitor.notify_security_event(:security_error, {
#     exception: exception,
#     request_details: extract_request_details
#   })
#
#   render plain: "Security Error", status: :forbidden
# end
