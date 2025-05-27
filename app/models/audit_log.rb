# frozen_string_literal: true

class AuditLog < ApplicationRecord
  # ポリモーフィック関連
  belongs_to :auditable, polymorphic: true
  belongs_to :user, optional: true, class_name: "Admin"

  # バリデーション
  validates :action, presence: true
  validates :message, presence: true

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_user, ->(user_id) { where(user_id: user_id) }
  scope :by_date_range, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # 列挙型：操作タイプ
  enum action: {
    create: "create",
    update: "update",
    delete: "delete",
    view: "view",
    export: "export",
    import: "import",
    login: "login",
    logout: "logout"
  }, _suffix: :action

  # インスタンスメソッド
  def user_display_name
    user&.email || "システム"
  end

  def formatted_created_at
    created_at.strftime("%Y年%m月%d日 %H:%M:%S")
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
