# frozen_string_literal: true

# CSP違反レポート収集コントローラー
# ============================================
# Phase 5-3: セキュリティ強化
# Content Security Policy違反の監視・分析
# ============================================
class CspReportsController < ApplicationController
  # CSRFトークン検証をスキップ（CSPレポートはブラウザが直接送信）
  skip_before_action :verify_authenticity_token
  
  # セキュリティヘッダーも不要（無限ループ防止）
  skip_before_action :set_security_headers
  
  # レート制限（Phase 5-1のRateLimiterを使用）
  include RateLimitable

  # CSP違反レポートの受信
  def create
    # レポートデータの取得
    report_data = parse_csp_report
    
    if report_data.present?
      # 監査ログに記録
      log_csp_violation(report_data)
      
      # 重大な違反の場合はアラート
      alert_if_critical(report_data)
      
      head :no_content
    else
      head :bad_request
    end
  end

  private

  # CSPレポートのパース
  def parse_csp_report
    return nil unless request.content_type =~ /application\/csp-report/
    
    begin
      report = JSON.parse(request.body.read)
      csp_report = report['csp-report'] || report
      
      {
        document_uri: csp_report['document-uri'],
        referrer: csp_report['referrer'],
        violated_directive: csp_report['violated-directive'],
        effective_directive: csp_report['effective-directive'],
        original_policy: csp_report['original-policy'],
        blocked_uri: csp_report['blocked-uri'],
        status_code: csp_report['status-code'],
        source_file: csp_report['source-file'],
        line_number: csp_report['line-number'],
        column_number: csp_report['column-number'],
        sample: csp_report['script-sample']
      }
    rescue JSON::ParserError => e
      Rails.logger.error "CSP report parse error: #{e.message}"
      nil
    end
  end

  # CSP違反の監査ログ記録
  def log_csp_violation(report_data)
    AuditLog.log_action(
      nil,
      'security_event',
      "CSP違反を検出: #{report_data[:violated_directive]}",
      {
        event_type: 'csp_violation',
        severity: determine_severity(report_data),
        csp_report: report_data,
        user_agent: request.user_agent,
        ip_address: request.remote_ip
      }
    )
  rescue => e
    Rails.logger.error "CSP violation logging failed: #{e.message}"
  end

  # 重大度の判定
  def determine_severity(report_data)
    blocked_uri = report_data[:blocked_uri]
    directive = report_data[:violated_directive]
    
    # スクリプト実行の試みは重大
    if directive =~ /script-src/ && blocked_uri !~ /^(self|data:)/
      'critical'
    # 外部リソースの読み込みは警告
    elsif blocked_uri =~ /^https?:\/\// && blocked_uri !~ /#{request.host}/
      'warning'
    # その他は情報レベル
    else
      'info'
    end
  end

  # 重大な違反の場合のアラート
  def alert_if_critical(report_data)
    severity = determine_severity(report_data)
    
    if severity == 'critical'
      # TODO: Phase 5-4 - セキュリティチームへの自動通知
      # SecurityAlertJob.perform_later(
      #   alert_type: 'csp_violation',
      #   severity: 'critical',
      #   details: report_data
      # )
      
      Rails.logger.error({
        event: 'critical_csp_violation',
        report: report_data,
        timestamp: Time.current.iso8601
      }.to_json)
    end
  end

  # ============================================
  # レート制限設定
  # ============================================
  
  def rate_limited_actions
    [:create]
  end
  
  def rate_limit_key_type
    :api  # APIレート制限を使用
  end
  
  def rate_limit_identifier
    # IPアドレスで識別
    request.remote_ip
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 CSP違反パターン分析
#    - 機械学習による異常検知
#    - 攻撃パターンの自動識別
#    - ホワイトリスト自動生成
#
# 2. 🟡 リアルタイムダッシュボード
#    - CSP違反の可視化
#    - 時系列グラフ表示
#    - 地理的分布表示
#
# 3. 🟢 自動対応機能
#    - 既知の誤検知フィルタリング
#    - CSPポリシーの自動調整
#    - インシデント対応の自動化