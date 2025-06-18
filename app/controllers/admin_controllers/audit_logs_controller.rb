# frozen_string_literal: true

module AdminControllers
  # 監査ログ管理コントローラー
  # ============================================
  # Phase 5-2: セキュリティ強化
  # 監査ログの閲覧・検索・エクスポート機能
  # CLAUDE.md準拠: GDPR/PCI DSS対応
  # ============================================
  class AuditLogsController < BaseController
    include AuditLogViewer

    before_action :authorize_audit_log_access!
    before_action :set_audit_log, only: [ :show ]

    # ============================================
    # アクション
    # ============================================

    # 監査ログ一覧
    def index
      @audit_logs = filter_audit_logs
                   .page(params[:page])
                   .per(per_page)

      # 統計情報
      @stats = audit_log_stats(@audit_logs.except(:limit, :offset))

      # 異常検知
      @anomalies = detect_anomalies(nil, 1.hour)

      respond_to do |format|
        format.html
        format.json { render json: @audit_logs }
        format.csv do
          send_data export_audit_logs(@audit_logs.except(:limit, :offset), :csv),
                    filename: "audit_logs_#{Date.current}.csv",
                    type: "text/csv"
        end
      end
    end

    # 監査ログ詳細
    def show
      # 関連する監査ログ
      if @audit_log.auditable
        @related_logs = AuditLog.where(
          auditable_type: @audit_log.auditable_type,
          auditable_id: @audit_log.auditable_id
        ).where.not(id: @audit_log.id)
         .recent
         .limit(10)
      end

      # この操作自体も監査ログに記録
      @audit_log.audit_view(current_admin, {
        viewer_role: current_admin.role,
        access_reason: params[:reason]
      })
    end

    # セキュリティイベント
    def security_events
      @security_events = AuditLog.security_events
                                .includes(:user)
                                .recent
                                .page(params[:page])
                                .per(per_page)

      # セキュリティ統計
      @security_stats = {
        total_events: @security_events.except(:limit, :offset).count,
        rate_limit_blocks: @security_events.except(:limit, :offset)
                                         .where("details LIKE ?", "%rate_limit_exceeded%")
                                         .count,
        failed_logins: AuditLog.where(action: "failed_login")
                              .where(created_at: 24.hours.ago..Time.current)
                              .count,
        permission_changes: AuditLog.where(action: "permission_change")
                                  .where(created_at: 7.days.ago..Time.current)
                                  .count
      }

      # 高リスクユーザー
      @high_risk_users = identify_high_risk_users
    end

    # ユーザー別監査履歴
    def user_activity
      @user = Admin.find(params[:user_id])
      @activities = @user.audit_logs
                        .includes(:auditable)
                        .recent
                        .page(params[:page])
                        .per(per_page)

      # ユーザー行動分析
      @user_stats = {
        total_actions: @activities.except(:limit, :offset).count,
        actions_breakdown: @activities.except(:limit, :offset).group(:action).count,
        active_hours: @activities.except(:limit, :offset)
                                .group_by_hour_of_day(:created_at)
                                .count,
        accessed_models: @activities.except(:limit, :offset)
                                  .group(:auditable_type)
                                  .count
      }

      # 異常検知
      @user_anomalies = detect_anomalies(@user.id, 1.hour)
    end

    # コンプライアンスレポート
    def compliance_report
      @start_date = params[:start_date] ? Date.parse(params[:start_date]) : 1.month.ago.to_date
      @end_date = params[:end_date] ? Date.parse(params[:end_date]) : Date.current

      @report_data = generate_compliance_report(@start_date, @end_date)

      respond_to do |format|
        format.html
        format.pdf do
          # TODO: PDF生成機能の実装
          render plain: "PDF export not yet implemented", status: :not_implemented
        end
      end
    end

    private

    # ============================================
    # 認可
    # ============================================

    # 🔒 セキュリティ修正: 監査ログアクセス権限の正しい実装
    # CLAUDE.md準拠: 現在のrole enumに基づく適切な権限チェック
    # メタ認知: 監査ログは最高権限（本部管理者）のみアクセス可能とする
    # TODO: 🔴 Phase 5（緊急）- super_admin権限実装後の権限チェック拡張
    #   - super_admin権限実装後: super_admin? || admin? に変更
    #   - より細かい権限制御（読み取り専用 vs 編集権限）
    #   - セキュリティ要件: 最小権限原則の厳格な適用
    def authorize_audit_log_access!
      unless current_admin.headquarters_admin?
        redirect_to admin_root_path,
                    alert: "監査ログへのアクセス権限がありません。本部管理者権限が必要です。"
      end
    end

    # ============================================
    # データ取得
    # ============================================

    def set_audit_log
      @audit_log = AuditLog.find(params[:id])
    end

    # 高リスクユーザーの特定
    def identify_high_risk_users
      # 24時間以内の活動を分析
      recent_window = 24.hours.ago

      high_risk_users = []

      # 失敗ログインが多いユーザー
      failed_login_users = AuditLog.where(action: "failed_login", created_at: recent_window..Time.current)
                                  .group(:user_id)
                                  .count
                                  .select { |_, count| count > 3 }

      failed_login_users.each do |user_id, count|
        user = Admin.find_by(id: user_id)
        next unless user

        high_risk_users << {
          user: user,
          risk_type: "multiple_failed_logins",
          risk_score: count * 20,
          details: "#{count}回のログイン失敗"
        }
      end

      # 大量データアクセス
      mass_access_users = AuditLog.where(action: %w[view export], created_at: recent_window..Time.current)
                                 .group(:user_id)
                                 .count
                                 .select { |_, count| count > 100 }

      mass_access_users.each do |user_id, count|
        user = Admin.find_by(id: user_id)
        next unless user

        existing = high_risk_users.find { |h| h[:user].id == user.id }
        if existing
          existing[:risk_score] += count / 10
          existing[:details] += ", #{count}件の大量アクセス"
        else
          high_risk_users << {
            user: user,
            risk_type: "mass_data_access",
            risk_score: count / 10,
            details: "#{count}件の大量データアクセス"
          }
        end
      end

      high_risk_users.sort_by { |h| -h[:risk_score] }
    end

    # コンプライアンスレポート生成
    def generate_compliance_report(start_date, end_date)
      logs = AuditLog.by_date_range(start_date, end_date)

      {
        period: {
          start: start_date,
          end: end_date
        },
        summary: {
          total_events: logs.count,
          unique_users: logs.distinct.count(:user_id),
          data_modifications: logs.where(action: %w[create update delete]).count,
          data_access: logs.where(action: %w[view export]).count,
          security_events: logs.security_events.count,
          authentication_events: logs.authentication_events.count
        },
        user_activities: logs.group(:user_id).count.map { |user_id, count|
          {
            user: Admin.find_by(id: user_id)&.email || "削除済みユーザー",
            activity_count: count
          }
        }.sort_by { |a| -a[:activity_count] },
        data_access_summary: logs.where(action: %w[view export])
                                .group(:auditable_type)
                                .count,
        security_summary: {
          failed_logins: logs.where(action: "failed_login").count,
          permission_changes: logs.where(action: "permission_change").count,
          password_changes: logs.where(action: "password_change").count
        },
        daily_breakdown: logs.group_by_day(:created_at).count
      }
    end
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 高度な分析機能
#    - 機械学習による異常検知
#    - 予測分析
#    - リスクスコアリング
#
# 2. 🟡 外部連携
#    - SIEM統合
#    - SOCへの自動通知
#    - 外部監査システム連携
#
# 3. 🟢 レポート機能強化
#    - カスタムレポート作成
#    - 定期レポート自動送信
#    - ダッシュボード統合
