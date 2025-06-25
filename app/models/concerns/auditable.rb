# frozen_string_literal: true

# 監査ログ自動記録機能を提供するConcern
# ============================================
# Phase 5-2: セキュリティ強化
# 重要な操作を自動的に監査ログに記録
# CLAUDE.md準拠: GDPR/PCI DSS対応
# ============================================
module Auditable
  extend ActiveSupport::Concern

  included do
    # コールバック
    after_create :log_create_action
    after_update :log_update_action
    before_destroy :log_destroy_action

    # 関連
    # CLAUDE.md準拠: 監査ログの永続保存（GDPR/PCI DSS対応）
    # メタ認知: 監査証跡は法的要件のため削除不可、親レコード削除も制限
    # 横展開: InventoryLoggableと同様のパターン適用
    has_many :audit_logs, as: :auditable, dependent: :restrict_with_error

    # クラス属性
    class_attribute :audit_options, default: {}
    class_attribute :audit_enabled, default: true
  end

  # ============================================
  # クラスメソッド
  # ============================================
  class_methods do
    # 監査オプションの設定
    def auditable(options = {})
      self.audit_options = {
        except: [],        # 除外するフィールド
        only: [],          # 含めるフィールド（指定時は他は除外）
        sensitive: [],     # 機密フィールド（マスキング対象）
        track_associations: false,  # 関連の変更も追跡
        if: -> { true },   # 条件付き監査
        unless: -> { false }
      }.merge(options)
    end

    # 監査を一時的に無効化
    def without_auditing
      original_value = audit_enabled
      self.audit_enabled = false
      yield
    ensure
      self.audit_enabled = original_value
    end

    # ユーザーの監査履歴を取得
    def audit_history(user_id, start_date = nil, end_date = nil)
      query = AuditLog.where(user_id: user_id)

      if start_date
        query = query.where("created_at >= ?", start_date.beginning_of_day)
      end

      if end_date
        query = query.where("created_at <= ?", end_date.end_of_day)
      end

      query.order(created_at: :desc)
    end

    # 監査ログの一括取得
    def audit_trail(options = {})
      query = AuditLog.where(auditable_type: self.name)

      # 特定のレコードのみ取得
      if options[:id]
        query = query.where(auditable_id: options[:id])
      end

      # 期間指定
      if options[:start_date] && options[:end_date]
        query = query.where(created_at: options[:start_date]..options[:end_date])
      end

      # アクション指定
      if options[:action]
        query = query.where(action: options[:action])
      end

      # ユーザー指定
      if options[:user_id]
        query = query.where(user_id: options[:user_id])
      end

      # ソートオプション
      sort_column = options[:sort] || "created_at"
      sort_direction = options[:direction] || "desc"
      query = query.order("#{sort_column} #{sort_direction}")

      # 関連レコードの取得
      if options[:include_related]
        query = query.includes(:user, :auditable)
      end

      query
    end

    # 監査サマリーの取得
    def audit_summary(options = {})
      trail = audit_trail(options)

      {
        total_count: trail.count,
        action_counts: trail.group(:action).count,
        user_counts: trail.group(:user_id).count,
        recent_activity_trend: calculate_audit_trend(trail),
        latest: trail.limit(10)
      }
    end

    # 監査ログのトレンド分析
    def calculate_audit_trend(trail)
      week_ago = 1.week.ago
      two_weeks_ago = 2.weeks.ago

      current_week_count = trail.where(created_at: week_ago..Time.current).count
      previous_week_count = trail.where(created_at: two_weeks_ago..week_ago).count

      trend_percentage = previous_week_count.zero? ? 0.0 :
                        ((current_week_count - previous_week_count).to_f / previous_week_count * 100).round(1)

      {
        current_week_count: current_week_count,
        previous_week_count: previous_week_count,
        trend_percentage: trend_percentage,
        is_increasing: current_week_count > previous_week_count
      }
    end
  end

  # ============================================
  # インスタンスメソッド
  # ============================================

  # 監査ユーザーの取得
  def audit_user
    Current.user || Current.admin || Current.store_user
  end

  # 監査用の変更内容取得
  def audit_changes
    saved_changes.except("updated_at", "created_at")
  end

  # 監査ログ記録対象となる識別名
  def auditable_name
    model_display_name
  end

  # 手動での監査ログ記録
  def audit_log(action, message, details = {})
    return unless audit_enabled

    AuditLog.log_action(
      self,
      action,
      message,
      details.merge(
        model_class: self.class.name,
        record_id: id
      )
    )
  end

  # 特定操作の監査メソッド
  def audit_view(viewer = nil, details = {})
    audit_log("view", "#{model_display_name}を参照しました",
              details.merge(viewer_id: viewer&.id))
  end

  def audit_export(format = nil, details = {})
    audit_log("export", "#{model_display_name}をエクスポートしました",
              details.merge(export_format: format))
  end

  def audit_import(source = nil, details = {})
    audit_log("import", "データをインポートしました",
              details.merge(import_source: source))
  end

  # セキュリティイベントの記録
  def audit_security_event(event_type, message, details = {})
    audit_log(event_type, message, details.merge(
      security_event: true,
      severity: details[:severity] || "medium"
    ))
  end

  private

  # ============================================
  # 監査ログ記録
  # ============================================

  # 作成時のログ
  def log_create_action
    return unless should_audit?

    AuditLog.log_action(
      self,
      "create",
      build_create_message,
      {
        attributes: sanitized_attributes,
        model_class: self.class.name
      },
      audit_user
    )
  rescue => e
    handle_audit_error(e)
  end

  # 更新時のログ
  def log_update_action
    return unless should_audit?
    # CLAUDE.md準拠: ベストプラクティス - updated_atのみの変更は監査対象外
    # メタ認知: touchメソッドなどでupdated_atのみが変更された場合はログ不要
    meaningful_changes = saved_changes.except("updated_at", "created_at")
    return if meaningful_changes.empty?

    AuditLog.log_action(
      self,
      "update",
      build_update_message,
      {
        changes: sanitized_changes,
        model_class: self.class.name,
        changed_fields: meaningful_changes.keys
      },
      audit_user
    )
  rescue => e
    handle_audit_error(e)
  end

  # 削除時のログ
  def log_destroy_action
    return unless should_audit?

    AuditLog.log_action(
      self,
      "delete",
      build_destroy_message,
      {
        attributes: sanitized_attributes,
        model_class: self.class.name
      },
      audit_user
    )
  rescue => e
    handle_audit_error(e)
  end

  # ============================================
  # メッセージ生成
  # ============================================

  def build_create_message
    "#{model_display_name}を作成しました"
  end

  def build_update_message
    # CLAUDE.md準拠: ベストプラクティス - 意味のある変更のみを表示
    changed_fields = saved_changes.keys - [ "updated_at", "created_at" ]
    "#{model_display_name}を更新しました（#{changed_fields.join(', ')}）"
  end

  def build_destroy_message
    "#{model_display_name}を削除しました"
  end

  def model_display_name
    # CLAUDE.md準拠: ベストプラクティス - 一貫性のあるモデル名表示
    # メタ認知: テストではモデル名がスペース区切りになる場合があるため統一
    model_name = self.class.name.gsub(/([A-Z]+)([A-Z][a-z])/, '\1 \2')
                               .gsub(/([a-z\d])([A-Z])/, '\1 \2')
                               .strip

    if respond_to?(:name)
      "#{model_name}「#{name}」"
    elsif respond_to?(:email)
      "#{model_name}「#{email}」"
    else
      "#{model_name}(ID: #{id})"
    end
  end

  # ============================================
  # 属性のサニタイズ
  # ============================================

  def sanitized_attributes
    attrs = attributes.dup

    # システムフィールドの除外
    attrs = attrs.except("created_at", "updated_at", "id")

    # 除外フィールドの削除
    if audit_options[:only].present?
      attrs = attrs.slice(*audit_options[:only].map(&:to_s))
    elsif audit_options[:except].present?
      attrs = attrs.except(*audit_options[:except].map(&:to_s))
    end

    # 機密フィールドのマスキング
    mask_sensitive_fields(attrs)
  end

  def sanitized_changes
    changes = saved_changes.dup

    # 除外フィールドの削除
    if audit_options[:only].present?
      changes = changes.slice(*audit_options[:only].map(&:to_s))
    elsif audit_options[:except].present?
      changes = changes.except(*audit_options[:except].map(&:to_s))
    end

    # CLAUDE.md準拠: ベストプラクティス - 変更内容は属性と同じルールでマスキング
    # メタ認知: 変更内容のマスキングは属性のマスキングと一貫性を保つ
    changes.each do |key, values|
      # 設定された機密フィールドのみマスキング
      if audit_options[:sensitive].include?(key.to_sym)
        changes[key] = [ "[FILTERED]", "[FILTERED]" ]
      else
        # 特定のフィールド名パターンに基づくマスキング
        case key.to_s
        when /credit_card/, /card_number/
          changes[key] = [ "[CARD_NUMBER]", "[CARD_NUMBER]" ]
        when /ssn/, /social_security/
          changes[key] = [ "[SSN]", "[SSN]" ]
        when /my_number/, /mynumber/
          changes[key] = [ "[MY_NUMBER]", "[MY_NUMBER]" ]
        when /secret_data/
          changes[key] = [ mask_if_sensitive(values[0]), mask_if_sensitive(values[1]) ]
        end
      end
    end

    changes
  end

  def mask_sensitive_fields(attrs)
    # CLAUDE.md準拠: セキュリティ最優先 - 機密情報の確実なマスキング
    # メタ認知: 明示的に機密指定されたフィールドのみマスキング
    # ベストプラクティス: 過度なマスキングは監査ログの有用性を損なうため避ける

    # 設定された機密フィールド
    audit_options[:sensitive].each do |field|
      if attrs.key?(field.to_s)
        attrs[field.to_s] = "[FILTERED]"
      end
    end

    # 一般的な機密フィールド
    %w[password password_confirmation encrypted_password reset_password_token].each do |field|
      attrs.delete(field)
    end

    # 特定のフィールド名に基づく機密情報の検出とマスキング
    # 横展開確認: クレジットカード、マイナンバーなど明らかに機密性の高いフィールドのみ
    sensitive_field_patterns = {
      /credit_card/ => "[CARD_NUMBER]",
      /card_number/ => "[CARD_NUMBER]",
      /ssn/ => "[SSN]",
      /social_security/ => "[SSN]",
      /my_number/ => "[MY_NUMBER]",
      /mynumber/ => "[MY_NUMBER]",
      /secret_data/ => ->(value) { mask_if_sensitive(value) }
    }

    attrs.each do |key, value|
      sensitive_field_patterns.each do |pattern, replacement|
        if key.to_s.match?(pattern)
          attrs[key] = replacement.is_a?(Proc) ? replacement.call(value) : replacement
          break
        end
      end
    end

    attrs
  end

  def mask_if_sensitive(value)
    return value unless value.is_a?(String)

    # 機密情報パターンの検出とマスキング
    # クレジットカード番号
    value = value.gsub(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/, "[CARD_NUMBER]")

    # 社会保障番号（米国）
    value = value.gsub(/\b\d{3}-\d{2}-\d{4}\b/, "[SSN]")

    # マイナンバー（日本）
    value = value.gsub(/\b\d{4}\s?\d{4}\s?\d{4}\b/, "[MY_NUMBER]")

    # メールアドレス（部分マスキング）
    value = value.gsub(/([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/) do
      email_local = $1
      email_domain = $2
      masked_local = email_local[0..1] + "*" * [ email_local.length - 2, 3 ].min
      "#{masked_local}@#{email_domain}"
    end

    # 電話番号（部分マスキング）
    value = value.gsub(/(\+?\d{1,3}[-.\s]?)?\(?\d{2,4}\)?[-.\s]?\d{3,4}[-.\s]?\d{3,4}/) do |phone|
      phone[-4..-1] = "****" if phone.length > 7
      phone
    end

    value
  end

  # ============================================
  # 条件チェック
  # ============================================

  def should_audit?
    return false unless audit_enabled

    # 条件付き監査の評価
    if_condition = audit_options[:if]
    unless_condition = audit_options[:unless]

    if if_condition.respond_to?(:call)
      return false unless instance_exec(&if_condition)
    end

    if unless_condition.respond_to?(:call)
      return false if instance_exec(&unless_condition)
    end

    true
  end

  # ============================================
  # エラーハンドリング
  # ============================================

  def handle_audit_error(error)
    # ログ記録に失敗しても主処理は継続
    Rails.logger.error("監査ログ記録エラー: #{error.message}")
    Rails.logger.error(error.backtrace.join("\n")) if Rails.env.development?

    # TODO: Phase 5-3 - エラー監視サービスへの通知
    # Sentry.capture_exception(error) if defined?(Sentry)
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 不正検知機能
#    - 異常なアクセスパターンの検出
#    - 権限外操作の監視
#    - リスクスコア算出機能
#
# 2. 🟡 コンプライアンス対応
#    - SOX法対応レポート
#    - GDPR対応データ削除記録
#    - 法的証跡として有効な形式でのエクスポート
#
# 3. 🟢 分析・可視化機能
#    - ユーザー操作の可視化ダッシュボード
#    - 操作頻度とパフォーマンス分析
#    - セキュリティインシデント分析
