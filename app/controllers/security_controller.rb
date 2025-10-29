# frozen_string_literal: true

# セキュリティ関連のコントローラー
# ================================
# - CSP違反レポートの受信
# - セキュリティ情報の提供
# - セキュリティ監査ログの記録
# ================================

class SecurityController < ApplicationController
  # CSPレポートは認証不要
  skip_before_action :verify_authenticity_token, only: [ :csp_report ]

  # CSP違反レポートの受信
  def csp_report
    if request.content_type == "application/csp-report"
      report_data = JSON.parse(request.body.read)

      # セキュリティログに記録
      log_csp_violation(report_data)

      # 重要な違反の場合は通知
      notify_security_team(report_data) if critical_violation?(report_data)

      head :no_content
    else
      head :bad_request
    end
  rescue JSON::ParserError => e
    Rails.logger.warn "[SECURITY] Invalid CSP report: #{e.message}"
    head :bad_request
  end

  # セキュリティ情報の提供
  def security_info
    render json: {
      version: Rails.application.config.version,
      last_updated: "2025-06-26",
      security_features: {
        https_only: Rails.application.config.force_ssl,
        csp_enabled: true,
        rate_limiting: defined?(Rack::Attack),
        security_headers: true
      },
      contact: {
        email: "security@stockrx.example.com",
        policy: "/security.txt"
      }
    }
  end

  # セキュリティ監査情報（管理者のみ）
  def audit_summary
    authenticate_admin!

    # 最近のセキュリティイベント
    recent_events = gather_security_events

    render json: {
      summary: {
        total_events: recent_events.count,
        critical_events: recent_events.select { |e| e[:severity] == "critical" }.count,
        last_incident: recent_events.first&.dig(:timestamp)
      },
      events: recent_events.first(50) # 最新50件
    }
  end

  private

  # CSP違反をログに記録
  def log_csp_violation(report_data)
    csp_report = report_data["csp-report"] || report_data

    violation_info = {
      timestamp: Time.current.iso8601,
      user_agent: request.user_agent,
      ip_address: request.remote_ip,
      document_uri: csp_report["document-uri"],
      referrer: csp_report["referrer"],
      violated_directive: csp_report["violated-directive"],
      blocked_uri: csp_report["blocked-uri"],
      source_file: csp_report["source-file"],
      line_number: csp_report["line-number"],
      column_number: csp_report["column-number"]
    }

    Rails.logger.warn "[CSP_VIOLATION] #{violation_info.to_json}"

    # 監査ログにも記録
    if defined?(AuditLog)
      AuditLog.create!(
        action: "csp_violation",
        resource_type: "Security",
        resource_id: nil,
        details: violation_info,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end
  end

  # 重要な違反かどうかを判定
  def critical_violation?(report_data)
    csp_report = report_data["csp-report"] || report_data
    violated_directive = csp_report["violated-directive"]
    blocked_uri = csp_report["blocked-uri"]

    # 重要な違反パターン
    critical_patterns = [
      /script-src.*eval/,
      /script-src.*data:/,
      /script-src.*javascript:/,
      /object-src/,
      /base-uri/
    ]

    # 悪意のあるドメインパターン
    malicious_domains = [
      /malware\./,
      /phishing\./,
      /suspicious\./,
      /\.tk$/,
      /\.ml$/,
      /\.ga$/
    ]

    critical_patterns.any? { |pattern| violated_directive.match(pattern) } ||
    malicious_domains.any? { |pattern| blocked_uri.match(pattern) }
  end

  # セキュリティチームへの通知
  def notify_security_team(report_data)
    # 本番環境でのみ通知
    return unless Rails.env.production?

    # Slack通知、メール通知などを実装
    Rails.logger.error "[SECURITY_ALERT] Critical CSP violation detected: #{report_data.to_json}"

    # 将来的にはSlackやEmail通知を実装
    # SecurityNotificationJob.perform_later(report_data)
  end

  # セキュリティイベントの収集
  def gather_security_events
    events = []

    # CSP違反ログ
    if defined?(AuditLog)
      csp_violations = AuditLog.where(action: "csp_violation")
                               .where("created_at > ?", 24.hours.ago)
                               .order(created_at: :desc)

      csp_violations.each do |violation|
        events << {
          type: "csp_violation",
          severity: critical_violation?(violation.details) ? "critical" : "warning",
          timestamp: violation.created_at.iso8601,
          details: violation.details
        }
      end
    end

    # Rack::Attack ログ（Redisから取得）
    if defined?(Rack::Attack)
      # 実装例：Redisからレート制限イベントを取得
      # rate_limit_events = Rack::Attack.cache.store.redis.keys('rack_attack:*')
    end

    # 失敗したログイン試行
    if defined?(Admin)
      failed_logins = Admin.where("failed_attempts > 0")
                           .where("locked_at IS NOT NULL OR locked_at > ?", 24.hours.ago)

      failed_logins.each do |admin|
        events << {
          type: "failed_login",
          severity: admin.failed_attempts > 10 ? "critical" : "warning",
          timestamp: admin.locked_at&.iso8601,
          details: {
            email: admin.email,
            failed_attempts: admin.failed_attempts,
            locked_at: admin.locked_at
          }
        }
      end
    end

    events.sort_by { |e| e[:timestamp] }.reverse
  end
end
