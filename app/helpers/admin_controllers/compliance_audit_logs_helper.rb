# frozen_string_literal: true

# ============================================================================
# ComplianceAuditLogsHelper - コンプライアンス監査ログ用ヘルパー
# ============================================================================
# CLAUDE.md準拠: Phase 1 セキュリティ機能強化
#
# 目的:
#   - コンプライアンス監査ログの表示ロジック
#   - セキュリティ情報の安全な表示
#   - レポート生成支援機能
#
# 設計思想:
#   - セキュリティ・バイ・デザイン原則
#   - 横展開: 他の監査ログヘルパーとの一貫性確保
#   - ベストプラクティス: 機密情報のマスキング強化
# ============================================================================

module AdminControllers
  module ComplianceAuditLogsHelper
    # ============================================================================
    # 表示フォーマット支援メソッド
    # ============================================================================

    # イベントタイプの日本語表示
    # @param event_type [String] イベントタイプ
    # @return [String] 日本語表示名
    def format_event_type(event_type)
      return "不明" if event_type.nil?

      event_type_translations = {
        "data_access" => "データアクセス",
        "login_attempt" => "ログイン試行",
        "data_export" => "データエクスポート",
        "data_import" => "データインポート",
        "unauthorized_access" => "不正アクセス",
        "data_breach" => "データ漏洩",
        "compliance_violation" => "コンプライアンス違反",
        "data_deletion" => "データ削除",
        "data_anonymization" => "データ匿名化",
        "card_data_access" => "カードデータアクセス",
        "personal_data_export" => "個人データエクスポート",
        "authentication_delay" => "認証遅延",
        "rate_limit_exceeded" => "レート制限超過",
        "encryption_key_rotation" => "暗号化キーローテーション"
      }

      event_type_translations[event_type] || event_type.to_s.humanize
    end

    # コンプライアンス標準の日本語表示
    # @param standard [String] コンプライアンス標準
    # @return [String] 日本語表示名
    def format_compliance_standard(standard)
      standard_translations = {
        "PCI_DSS" => "PCI DSS (クレジットカード情報保護)",
        "GDPR" => "GDPR (EU一般データ保護規則)",
        "SOX" => "SOX法 (サーベンス・オクスリー法)",
        "HIPAA" => "HIPAA (医療保険の相互運用性と説明責任に関する法律)",
        "ISO27001" => "ISO 27001 (情報セキュリティマネジメント)"
      }

      standard_translations[standard] || standard
    end

    # 重要度レベルのHTMLクラスとアイコン
    # @param severity [String] 重要度レベル
    # @return [Hash] CSSクラスとアイコン情報
    def severity_display_info(severity)
      severity_info = {
        "low" => {
          label: "低",
          css_class: "badge bg-secondary",
          icon: "bi-info-circle",
          color: "text-secondary"
        },
        "medium" => {
          label: "中",
          css_class: "badge bg-warning text-dark",
          icon: "bi-exclamation-triangle",
          color: "text-warning"
        },
        "high" => {
          label: "高",
          css_class: "badge bg-danger",
          icon: "bi-exclamation-circle",
          color: "text-danger"
        },
        "critical" => {
          label: "緊急",
          css_class: "badge bg-dark",
          icon: "bi-shield-exclamation",
          color: "text-danger"
        }
      }

      severity_info[severity] || severity_info["medium"]
    end

    # 重要度バッジのHTML生成
    # @param severity [String] 重要度レベル
    # @return [String] HTMLバッジ
    def severity_badge(severity)
      info = severity_display_info(severity)
      content_tag :span, info[:label], class: info[:css_class]
    end

    # ============================================================================
    # データ表示・マスキング機能
    # ============================================================================

    # 安全な詳細情報の表示
    # @param compliance_audit_log [ComplianceAuditLog] 監査ログ
    # @return [Hash] 表示用の安全な詳細情報
    def safe_details_for_display(compliance_audit_log)
      return {} unless compliance_audit_log

      begin
        details = compliance_audit_log.safe_details

        # 表示用にフォーマット
        formatted_details = {}
        details.each do |key, value|
          formatted_key = format_detail_key(key)
          formatted_value = format_detail_value(key, value)
          formatted_details[formatted_key] = formatted_value
        end

        formatted_details
      rescue => e
        Rails.logger.error "Failed to format compliance audit log details: #{e.message}"
        { "エラー" => "詳細情報の取得に失敗しました" }
      end
    end

    # ユーザー情報の安全な表示
    # @param user [Admin, StoreUser] ユーザーオブジェクト
    # @return [String] 表示用ユーザー情報
    def format_user_for_display(user)
      return "システム" unless user

      case user
      when Admin
        role_name = format_admin_role(user.role)
        store_info = user.store ? " (#{user.store.name})" : " (本部)"
        "#{user.name || user.email}#{store_info} [#{role_name}]"
      when StoreUser
        role_name = format_store_user_role(user.role)
        "#{user.name || user.email} (#{user.store.name}) [#{role_name}]"
      else
        "不明なユーザータイプ"
      end
    end

    # ============================================================================
    # 時間・期間表示機能
    # ============================================================================

    # 監査ログの作成日時フォーマット
    # @param compliance_audit_log [ComplianceAuditLog] 監査ログ
    # @return [String] フォーマット済み日時
    def format_audit_datetime(compliance_audit_log)
      return "不明" unless compliance_audit_log&.created_at

      created_at = compliance_audit_log.created_at
      "#{created_at.strftime('%Y年%m月%d日 %H:%M:%S')} (#{time_ago_in_words(created_at)}前)"
    end

    # 保持期限の表示
    # @param compliance_audit_log [ComplianceAuditLog] 監査ログ
    # @return [String] 保持期限情報
    def format_retention_status(compliance_audit_log)
      return "不明" unless compliance_audit_log

      expiry_date = compliance_audit_log.retention_expiry_date
      days_remaining = (expiry_date - Date.current).to_i

      if days_remaining > 0
        "#{expiry_date.strftime('%Y年%m月%d日')}まで (あと#{days_remaining}日)"
      else
        content_tag :span, "期限切れ (#{(-days_remaining)}日経過)", class: "text-danger"
      end
    end

    # ============================================================================
    # レポート・分析支援機能
    # ============================================================================

    # コンプライアンス標準別のサマリー情報
    # @param logs [ActiveRecord::Relation] 監査ログのコレクション
    # @return [Hash] 標準別サマリー
    def compliance_summary_by_standard(logs)
      summary = {}

      logs.group(:compliance_standard).group(:severity).count.each do |(standard, severity), count|
        summary[standard] ||= { total: 0, by_severity: {} }
        summary[standard][:total] += count
        summary[standard][:by_severity][severity] = count
      end

      summary
    end

    # 重要度別の統計情報
    # @param logs [ActiveRecord::Relation] 監査ログのコレクション
    # @return [Hash] 重要度別統計
    def severity_statistics(logs)
      stats = logs.group(:severity).count
      total = stats.values.sum

      return {} if total.zero?

      stats.transform_values do |count|
        {
          count: count,
          percentage: (count.to_f / total * 100).round(1)
        }
      end
    end

    # 期間別のアクティビティ傾向
    # @param logs [ActiveRecord::Relation] 監査ログのコレクション
    # @param period [Symbol] 期間タイプ (:daily, :weekly, :monthly)
    # @return [Hash] 期間別アクティビティ
    def activity_trend(logs, period = :daily)
      # GroupDateが利用できない場合の代替実装
      if Rails.env.test? || !defined?(Groupdate)
        case period
        when :daily
          { Date.current => logs.count }
        when :weekly
          { Date.current.beginning_of_week => logs.count }
        when :monthly
          { Date.current.beginning_of_month => logs.count }
        else
          {}
        end
      else
        case period
        when :daily
          logs.group_by_day(:created_at, last: 30).count
        when :weekly
          logs.group_by_week(:created_at, last: 12).count
        when :monthly
          logs.group_by_month(:created_at, last: 12).count
        else
          {}
        end
      end
    end

    # ============================================================================
    # 検索・フィルタリング支援
    # ============================================================================

    # 検索条件の表示
    # @param params [Hash] 検索パラメータ
    # @return [Array<String>] 検索条件の表示リスト
    def format_search_conditions(params)
      conditions = []

      if params[:compliance_standard].present?
        standard_name = format_compliance_standard(params[:compliance_standard])
        conditions << "標準: #{standard_name}"
      end

      if params[:severity].present?
        severity_info = severity_display_info(params[:severity])
        conditions << "重要度: #{severity_info[:label]}"
      end

      if params[:event_type].present?
        event_name = format_event_type(params[:event_type])
        conditions << "イベント: #{event_name}"
      end

      if params[:start_date].present? && params[:end_date].present?
        conditions << "期間: #{params[:start_date]} 〜 #{params[:end_date]}"
      elsif params[:start_date].present?
        conditions << "開始日: #{params[:start_date]} 以降"
      elsif params[:end_date].present?
        conditions << "終了日: #{params[:end_date]} 以前"
      end

      conditions.empty? ? [ "すべて" ] : conditions
    end

    private

    # ============================================================================
    # プライベートメソッド
    # ============================================================================

    # 詳細情報キーのフォーマット
    def format_detail_key(key)
      key_translations = {
        "timestamp" => "タイムスタンプ",
        "action" => "アクション",
        "user_id" => "ユーザーID",
        "user_role" => "ユーザー権限",
        "ip_address" => "IPアドレス",
        "user_agent" => "ユーザーエージェント",
        "result" => "結果",
        "compliance_context" => "コンプライアンス文脈",
        "details" => "詳細",
        "legal_basis" => "法的根拠",
        "attempt_count" => "試行回数",
        "delay_applied" => "適用遅延",
        "identifier" => "識別子"
      }

      key_translations[key.to_s] || key.to_s.humanize
    end

    # 詳細情報値のフォーマット
    def format_detail_value(key, value)
      case key.to_s
      when "timestamp"
        Time.parse(value).strftime("%Y年%m月%d日 %H:%M:%S") rescue value
      when "result"
        value == "success" ? "成功" : (value == "failure" ? "失敗" : value)
      when "legal_basis"
        format_legal_basis(value)
      else
        value.to_s
      end
    end

    # 法的根拠のフォーマット
    def format_legal_basis(basis)
      basis_translations = {
        "legitimate_interest" => "正当な利益",
        "consent" => "同意",
        "contract" => "契約履行",
        "legal_obligation" => "法的義務",
        "vital_interests" => "生命に関わる利益",
        "public_task" => "公的業務"
      }

      basis_translations[basis] || basis
    end

    # 管理者権限の表示
    def format_admin_role(role)
      admin_role_translations = {
        "store_user" => "一般店舗ユーザー",
        "pharmacist" => "薬剤師",
        "store_manager" => "店舗管理者",
        "headquarters_admin" => "本部管理者"
      }

      admin_role_translations[role] || role.humanize
    end

    # 店舗ユーザー権限の表示
    def format_store_user_role(role)
      store_user_role_translations = {
        "staff" => "スタッフ",
        "manager" => "マネージャー"
      }

      store_user_role_translations[role] || role.humanize
    end
  end
end

# ============================================
# TODO: 🟡 Phase 3（重要）- ヘルパー機能の拡張
# ============================================
# 優先度: 中（機能拡張）
#
# 【計画中の拡張機能】
# 1. 📊 高度なレポート機能
#    - PDF/Excelエクスポート支援
#    - グラフ・チャート生成支援
#    - カスタムレポートテンプレート
#
# 2. 🔍 検索・フィルタリング強化
#    - 高度な検索条件組み合わせ
#    - 保存済み検索条件
#    - クイックフィルター機能
#
# 3. 🎨 UI/UX向上
#    - ダークモード対応
#    - レスポンシブデザイン強化
#    - アクセシビリティ改善
#
# 4. 🚀 パフォーマンス最適化
#    - キャッシュ活用
#    - 遅延読み込み対応
#    - バッチ処理最適化
# ============================================
