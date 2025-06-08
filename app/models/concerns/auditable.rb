# frozen_string_literal: true

module Auditable
  extend ActiveSupport::Concern

  # TODO: パフォーマンス最適化
  # - 大量の監査ログ蓄積時のクエリ最適化
  # - 非同期ログ記録によるメイン処理への影響軽減
  # - パーティション機能による古いログの効率的管理
  #
  # TODO: 機能拡張
  # - JSON形式のdetailsフィールドの構造化検索機能
  # - ログレベル（info, warning, critical）の導入
  # - 操作前後の値変更の詳細トラッキング

  included do
    has_many :audit_logs, as: :auditable, dependent: :destroy

    # 監査ログを保存するコールバック
    after_create :log_create_action
    after_update :log_update_action
  end

  # インスタンスメソッド

  # 監査ログを記録するメソッド
  def audit_log(action, details = {})
    audit_logs.create!(
      user_id: defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil,
      action: action,
      details: details,
      ip_address: defined?(Current) && Current.respond_to?(:ip_address) ? Current.ip_address : nil,
      user_agent: defined?(Current) && Current.respond_to?(:user_agent) ? Current.user_agent : nil
    )
  end

  # 操作タイプごとの監査メソッド
  def audit_create(details = {})
    audit_log("create", details)
  end

  def audit_update(details = {})
    audit_log("update", details)
  end

  def audit_delete(details = {})
    audit_log("delete", details)
  end

  def audit_view(details = {})
    audit_log("view", details)
  end

  def audit_export(details = {})
    audit_log("export", details)
  end

  def audit_import(details = {})
    audit_log("import", details)
  end

  def audit_login(details = {})
    audit_log("login", details)
  end

  def audit_logout(details = {})
    audit_log("logout", details)
  end

  # 作成時のログ記録
  def log_create_action
    create_audit_log("create", "レコードを作成しました")
  end

  # 更新時のログ記録
  def log_update_action
    # 変更内容を記録
    changes_hash = saved_changes.except("updated_at", "created_at")
    return if changes_hash.empty?

    details = changes_hash.map do |attribute, (old_value, new_value)|
      "#{attribute}: #{old_value.inspect} → #{new_value.inspect}"
    end.join(", ")

    create_audit_log("update", "レコードを更新しました", details)
  end

  # 任意の操作のログ記録
  def log_custom_action(action, message, details = nil)
    create_audit_log(action, message, details)
  end

  private

  # 監査ログ作成の共通処理
  def create_audit_log(action, message, details = nil)
    # テスト環境でaudit_logsアソシエーションが存在しない場合は処理をスキップ
    return unless respond_to?(:audit_logs) && audit_logs.respond_to?(:create!)

    audit_logs.create!(
      action: action,
      message: message,
      details: details,
      user_id: current_user_id,
      ip_address: current_ip_address,
      user_agent: current_user_agent,
      operation_source: current_operation_source,
      operation_type: current_operation_type
    )
  rescue => e
    # ログ記録に失敗しても主処理は継続
    # TODO: エラーハンドリングの改善
    # - Sentry等の外部監視ツールへのエラー通知
    # - ログ記録失敗回数の監視とアラート機能
    # - フォールバック機能（ファイルベースログ等）
    Rails.logger.error("監査ログ記録エラー: #{e.message}")
  end

  # 現在のユーザーID取得
  def current_user_id
    defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil
  end

  # 現在のIP取得
  def current_ip_address
    defined?(Current) && Current.respond_to?(:ip_address) ? Current.ip_address : nil
  end

  # 現在のUserAgent取得
  def current_user_agent
    defined?(Current) && Current.respond_to?(:user_agent) ? Current.user_agent : nil
  end

  # 操作元取得
  def current_operation_source
    defined?(Current) && Current.respond_to?(:operation_source) ? Current.operation_source : nil
  end

  # 操作種別取得
  def current_operation_type
    defined?(Current) && Current.respond_to?(:operation_type) ? Current.operation_type : nil
  end

  class_methods do
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

    # 全ての監査ログをエクスポート
    def export_audit_logs(start_date = nil, end_date = nil)
      query = AuditLog.all

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
      table_name = self.table_name

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
        daily_counts: trail.group_by_day(:created_at).count,
        latest: trail.limit(10)
      }
    end

    # TODO: 監査機能の拡張
    # 1. 不正検知機能
    #    - 異常なアクセスパターンの検出
    #    - 権限外操作の監視
    #    - リスクスコア算出機能
    #
    # 2. コンプライアンス対応
    #    - SOX法対応レポート
    #    - GDPR対応データ削除記録
    #    - 法的証跡として有効な形式でのエクスポート
    #
    # 3. 分析・可視化機能
    #    - ユーザー操作の可視化ダッシュボード
    #    - 操作頻度とパフォーマンス分析
    #    - セキュリティインシデント分析
  end
end
