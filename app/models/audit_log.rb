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

  # TODO: 監査ログ機能の拡張
  # 1. ログの暗号化機能
  #    - 機密性の高い操作ログの暗号化保存
  #    - ログ検索時の復号化機能
  #    - 暗号化キーのローテーション機能
  #
  # 2. ログの完全性チェック機能
  #    - ハッシュチェーンによるログ改ざん検出
  #    - デジタル署名による真正性保証
  #    - ブロックチェーン技術を活用したログ保証
  #
  # 3. 高度な検索・分析機能
  #    - Elasticsearch連携による高速ログ検索
  #    - ログパターン分析による異常検知
  #    - 機械学習による不正アクセス検出
  #
  # 4. コンプライアンス対応
  #    - SOX法対応監査証跡の自動生成
  #    - GDPR対応個人データ削除ログ
  #    - ISO27001準拠ログ管理機能
end
