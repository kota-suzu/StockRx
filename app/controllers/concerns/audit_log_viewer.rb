# frozen_string_literal: true

# 監査ログ表示機能を提供するConcern
# ============================================
# Phase 5-2: セキュリティ強化
# 監査ログの表示・検索・フィルタリング機能
# ============================================
module AuditLogViewer
  extend ActiveSupport::Concern

  included do
    helper_method :audit_log_filters if respond_to?(:helper_method)
  end

  # 監査ログの検索・フィルタリング
  def filter_audit_logs(base_scope = AuditLog.all)
    scope = base_scope.includes(:user, :auditable)

    # アクションフィルタ
    if params[:action_filter].present?
      scope = scope.by_action(params[:action_filter])
    end

    # ユーザーフィルタ
    if params[:user_id].present?
      scope = scope.by_user(params[:user_id])
    end

    # 日付範囲フィルタ
    if params[:start_date].present? && params[:end_date].present?
      scope = scope.by_date_range(
        Date.parse(params[:start_date]).beginning_of_day,
        Date.parse(params[:end_date]).end_of_day
      )
    end

    # モデルタイプフィルタ
    if params[:auditable_type].present?
      scope = scope.where(auditable_type: params[:auditable_type])
    end

    # セキュリティイベントのみ
    if params[:security_only] == "true"
      scope = scope.security_events
    end

    # 検索クエリ
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      scope = scope.where(
        "message LIKE :term OR details LIKE :term",
        term: search_term
      )
    end

    scope.recent
  end

  # 監査ログのエクスポート
  def export_audit_logs(scope, format = :csv)
    case format
    when :csv
      generate_audit_csv(scope)
    when :json
      generate_audit_json(scope)
    else
      raise ArgumentError, "Unsupported format: #{format}"
    end
  end

  private

  # CSV生成
  def generate_audit_csv(logs)
    require "csv"

    CSV.generate(headers: true) do |csv|
      csv << [
        "ID",
        "日時",
        "操作",
        "ユーザー",
        "メッセージ",
        "対象",
        "IPアドレス",
        "詳細"
      ]

      logs.find_each do |log|
        csv << [
          log.id,
          log.created_at.strftime("%Y-%m-%d %H:%M:%S"),
          log.action,
          log.user_display_name,
          log.message,
          "#{log.auditable_type}##{log.auditable_id}",
          log.ip_address,
          log.details
        ]
      end
    end
  end

  # JSON生成
  def generate_audit_json(logs)
    logs.map do |log|
      {
        id: log.id,
        created_at: log.created_at.iso8601,
        action: log.action,
        user: {
          id: log.user_id,
          email: log.user&.email
        },
        message: log.message,
        auditable: {
          type: log.auditable_type,
          id: log.auditable_id
        },
        ip_address: log.ip_address,
        user_agent: log.user_agent,
        details: log.details ? JSON.parse(log.details) : nil
      }
    end.to_json
  end

  # フィルタオプション
  def audit_log_filters
    {
      actions: AuditLog.actions.keys.map { |action|
        [ I18n.t("audit_log.actions.#{action}", default: action.humanize), action ]
      },
      users: User.joins(:audit_logs)
                 .distinct
                 .pluck(:email, :id)
                 .map { |email, id| [ email, id ] },
      auditable_types: AuditLog.distinct
                               .pluck(:auditable_type)
                               .compact
                               .map { |type| [ type.humanize, type ] }
    }
  end

  # 監査ログの統計情報
  def audit_log_stats(scope = AuditLog.all)
    {
      total_count: scope.count,
      today_count: scope.where(created_at: Time.current.beginning_of_day..Time.current).count,
      actions_breakdown: scope.group(:action).count,
      users_breakdown: scope.group(:user_id).count,
      hourly_breakdown: scope.where(created_at: 24.hours.ago..Time.current)
                            .group_by_hour(:created_at)
                            .count,
      top_users: scope.group(:user_id)
                     .count
                     .sort_by { |_, count| -count }
                     .first(10)
                     .map { |user_id, count|
                       {
                         user: User.find_by(id: user_id),
                         count: count
                       }
                     }
    }
  end

  # 異常検知
  def detect_anomalies(user_id = nil, time_window = 1.hour)
    scope = user_id ? AuditLog.by_user(user_id) : AuditLog.all
    recent_logs = scope.where(created_at: time_window.ago..Time.current)

    anomalies = []

    # 短時間での大量アクセス検知
    if recent_logs.count > 100
      anomalies << {
        type: "high_activity",
        message: "高頻度のアクティビティを検出（#{recent_logs.count}件/#{time_window.inspect}）",
        severity: "warning"
      }
    end

    # 複数の失敗ログイン
    failed_logins = recent_logs.where(action: "failed_login").count
    if failed_logins > 5
      anomalies << {
        type: "multiple_failed_logins",
        message: "複数のログイン失敗を検出（#{failed_logins}件）",
        severity: "critical"
      }
    end

    # 権限変更の検知
    permission_changes = recent_logs.where(action: "permission_change").count
    if permission_changes > 0
      anomalies << {
        type: "permission_changes",
        message: "権限変更を検出（#{permission_changes}件）",
        severity: "info"
      }
    end

    # データの大量エクスポート
    exports = recent_logs.where(action: "export").count
    if exports > 10
      anomalies << {
        type: "mass_export",
        message: "大量のデータエクスポートを検出（#{exports}件）",
        severity: "warning"
      }
    end

    anomalies
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 機械学習による異常検知
#    - 通常パターンの学習
#    - 異常スコアの算出
#    - リアルタイムアラート
#
# 2. 🟡 可視化機能
#    - ダッシュボード統合
#    - グラフ・チャート生成
#    - ヒートマップ表示
#
# 3. 🟢 レポート自動生成
#    - 定期レポート
#    - コンプライアンスレポート
#    - インシデントレポート
