# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # ポリモーフィック関連
  belongs_to :auditable, polymorphic: true
  belongs_to :user, optional: true, class_name: "Admin"

  # CLAUDE.md準拠: ベストプラクティス - 意味的に正しい関連付け名の提供
  # メタ認知: 監査ログの操作者は管理者（admin）なので、adminエイリアスが意味的に適切
  # 横展開: InventoryLogと同様のパターン適用で一貫性確保
  # TODO: 🟡 Phase 3（重要）- ログ系モデル関連付け統一設計
  #   - user_idカラム名をadmin_idに統一するマイグレーション
  #   - InventoryLogとの一貫性確保
  #   - 監査ログ統合インターフェースの設計
  belongs_to :admin, optional: true, class_name: "Admin", foreign_key: "user_id"

  # バリデーション
  validates :action, presence: true
  validates :message, presence: true

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }
  scope :security_events, -> { where(action: %w[security_event failed_login permission_change password_change]) }
  scope :authentication_events, -> { where(action: %w[login logout failed_login]) }
  scope :data_access_events, -> { where(action: %w[view export]) }

  # 列挙型：操作タイプ（Rails 8 対応：位置引数使用）
  enum :action, {
    create: "create",
    update: "update",
    delete: "delete",
    view: "view",
    export: "export",
    import: "import",
    login: "login",
    logout: "logout",
    security_event: "security_event",
    permission_change: "permission_change",
    password_change: "password_change",
    failed_login: "failed_login"
  }, suffix: :action

  # インスタンスメソッド
  def user_display_name
    user&.email || "システム"
  end

  def formatted_created_at
    created_at.strftime("%Y年%m月%d日 %H:%M:%S")
  end

  # 監査ログ閲覧記録メソッド
  # CLAUDE.md準拠: セキュリティ機能強化 - 監査の監査
  # メタ認知: 監査ログ自体の閲覧も監査対象とすることでコンプライアンス要件を満たす
  # 横展開: ComplianceAuditLogでも同様の実装が必要
  def audit_view(viewer, details = {})
    # 無限ループ防止: 監査ログの閲覧記録自体は記録しない
    return if action == "view" && auditable_type == "AuditLog"

    # 監査ログの閲覧は重要なセキュリティイベントとして記録
    self.class.log_action(
      self,                           # auditable: この監査ログ自体
      "view",                         # action: 閲覧アクション
      "監査ログ(ID: #{id})が閲覧されました",  # message
      details.merge({                 # 詳細情報
        viewed_log_id: id,
        viewed_log_action: action,
        # セキュリティ: メッセージ内容は記録しない（機密情報保護）
        viewed_at: Time.current,
        viewer_role: viewer&.role,
        compliance_reason: details[:access_reason] || "通常閲覧"
      }),
      viewer                          # user: 閲覧者
    )
  rescue => e
    # エラー時も記録を試行（ベストエフォート）
    Rails.logger.error "監査ログ閲覧記録エラー: #{e.message}"
    nil
  end

  # クラスメソッド
  class << self
    def log_action(auditable, action, message, details = {}, user = nil)
      create!(
        auditable: auditable,
        action: action,
        message: message,
        details: details.to_json,
        user: user || Current.user,
        ip_address: Current.ip_address,
        user_agent: Current.user_agent
      )
    end

    def cleanup_old_logs(days = 90)
      where("created_at < ?", days.days.ago).delete_all
    end
  end

  # ============================================
  # TODO: 監査ログ機能の拡張計画
  # ============================================
  # 1. セキュリティ・コンプライアンス強化
  #    - デジタル署名による改ざん防止
  #    - ハッシュチェーンによる整合性検証
  #    - 暗号化による機密性保護
  #    - GDPR/SOX法対応の監査証跡
  #
  # 2. 高度な分析・監視
  #    - 異常操作パターンの自動検出
  #    - 機械学習による不正行為検知
  #    - リスクスコアの自動計算
  #    - リアルタイム監視ダッシュボード
  #
  # 3. レポート・可視化
  #    - 包括的監査レポートの自動生成
  #    - 操作頻度のヒートマップ
  #    - タイムライン可視化
  #    - Excel/PDF エクスポート機能
  #
  # 4. 統合・連携機能
  #    - SIEM（Security Information and Event Management）連携
  #    - 外部監査システムとのAPI連携
  #    - Active Directory連携による統合認証
  #    - Webhook による外部通知
  #
  # 5. パフォーマンス・スケーラビリティ
  #    - 大量ログデータの効率的処理
  #    - ログアーカイブ・圧縮機能
  #    - 分散ストレージ対応
  #    - 検索性能の最適化
  #
  # 6. 業界特化機能
  #    - 医薬品業界のGMP（Good Manufacturing Practice）対応
  #    - 食品業界のHACCP（Hazard Analysis and Critical Control Points）対応
  #    - 金融業界の内部統制対応
  #    - 製造業のISO9001品質管理対応
end
