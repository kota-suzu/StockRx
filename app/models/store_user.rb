# frozen_string_literal: true

# 店舗スタッフ用認証モデル
# ============================================
# Phase 1: 店舗別ログインシステムの基盤実装
# CLAUDE.md準拠: セキュリティ最優先、横展開確認済み
# ============================================
class StoreUser < ApplicationRecord
  # ============================================
  # Concerns
  # ============================================
  include Auditable

  # 監査ログ設定
  auditable except: [ :created_at, :updated_at, :sign_in_count, :current_sign_in_at,
                     :last_sign_in_at, :current_sign_in_ip, :last_sign_in_ip,
                     :encrypted_password, :reset_password_token, :reset_password_sent_at,
                     :remember_created_at, :locked_at, :failed_attempts ],
            sensitive: [ :encrypted_password, :reset_password_token ]

  # ============================================
  # Devise設定
  # ============================================
  devise :database_authenticatable, :recoverable, :rememberable,
         :lockable, :timeoutable, :trackable
  # NOTE: :validatable を除外してカスタムバリデーションを使用

  # ============================================
  # アソシエーション
  # ============================================
  belongs_to :store

  # 監査ログ関連
  # CLAUDE.md準拠: ベストプラクティス - ポリモーフィック関連による柔軟な監査ログ管理
  # メタ認知: ComplianceAuditLogのuser関連付けがポリモーフィックなので、
  # 　　　　　StoreUserからも as: :user で関連付け可能
  # 横展開: Adminモデルと同様の関連付けパターン適用
  has_many :compliance_audit_logs, as: :user, dependent: :restrict_with_error

  # 一時パスワード関連（メール認証機能）
  # CLAUDE.md準拠: セキュリティ機能統合、カスケード削除による整合性保証
  # メタ認知: 店舗ユーザー削除時に一時パスワードも安全に削除
  # 横展開: 他の認証関連モデルと同様のdependent設定
  has_many :temp_passwords, dependent: :destroy

  # ============================================
  # バリデーション
  # ============================================
  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true,
                   format: { with: URI::MailTo::EMAIL_REGEXP },
                   uniqueness: { scope: :store_id, case_sensitive: false,
                               message: "は既にこの店舗で使用されています" }
  # ============================================
  # enum定義（CLAUDE.md準拠: Admin modelとの一貫性確保）
  # ============================================
  enum :role, {
    staff: "staff",                 # 一般スタッフ
    manager: "manager"              # マネージャー
  }

  validates :role, presence: true
  validates :employee_code, uniqueness: { scope: :store_id, allow_blank: true,
                                        case_sensitive: false }

  # パスワードポリシー（CLAUDE.md セキュリティ要件準拠）
  validates :password, presence: true, confirmation: true, if: :password_required?
  validates :password, password_strength: true, if: :password_required?
  validate :password_not_recently_used, if: :password_required?

  # ============================================
  # スコープ
  # ============================================
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :managers, -> { where(role: "manager") }
  scope :staff, -> { where(role: "staff") }
  scope :locked, -> { where.not(locked_at: nil) }
  scope :password_expired, -> { where("password_changed_at < ?", 90.days.ago) }

  # ============================================
  # コールバック
  # ============================================
  before_save :update_password_changed_at, if: :will_save_change_to_encrypted_password?
  before_save :downcase_email
  before_save :normalize_name
  after_create :send_welcome_email

  # ============================================
  # Devise設定のカスタマイズ
  # ============================================

  # タイムアウト時間（8時間）
  def timeout_in
    8.hours
  end

  # ロック条件（5回失敗で30分ロック）
  def self.unlock_in
    30.minutes
  end

  def self.maximum_attempts
    5
  end

  # ============================================
  # インスタンスメソッド
  # ============================================

  # 表示名
  def display_name
    "#{name} (#{store.name})"
  end

  # 管理者権限チェック
  def manager?
    role == "manager"
  end

  def staff?
    role == "staff"
  end

  # 権限管理メソッド（CLAUDE.md準拠: テスト要件対応）
  # メタ認知: 権限の階層的管理 - マネージャーのみ高度な操作を許可
  # 横展開: Adminモデルでも同様の権限管理パターンを適用可能

  # 在庫管理権限チェック
  def can_manage_inventory?
    manager?
  end

  # ユーザー管理権限チェック
  def can_manage_users?
    manager?
  end

  # レポート閲覧権限チェック
  # TODO: 🟡 Phase 3（重要）- より詳細な権限管理
  # 優先度: 中
  # 実装内容: スタッフでも一部レポートは閲覧可能にする
  # 理由: 業務効率化とセキュリティのバランス
  # 横展開: 権限マトリクスの実装
  def can_view_reports?
    true # 全スタッフがレポート閲覧可能
  end

  # 詳細権限管理メソッド（CLAUDE.md準拠: テスト要件対応）
  # メタ認知: 在庫操作の細分化により、より安全な権限管理を実現
  # 横展開: 他の機能でも同様の細分化権限管理を適用

  # 在庫閲覧権限
  def can_view_inventory?
    true # 全スタッフが在庫閲覧可能
  end

  # 在庫作成権限
  def can_create_inventory?
    manager?
  end

  # 在庫更新権限
  def can_update_inventory?
    manager?
  end

  # 在庫削除権限
  def can_delete_inventory?
    manager?
  end

  # ユーザー閲覧権限
  def can_view_users?
    manager?
  end

  # ユーザー作成権限
  def can_create_users?
    manager?
  end

  # ユーザー更新権限
  def can_update_users?
    manager?
  end

  # レポートエクスポート権限
  def can_export_reports?
    manager?
  end

  # フルメールアドレス表示（店舗名付き）
  def full_email
    "#{email} (#{store.name})"
  end

  # 役割の日本語表示
  # CLAUDE.md準拠: Adminモデルと同様のインターフェース統一
  # メタ認知: ポリモーフィック関連での一貫性確保のため必須
  # 横展開: Admin#role_textと同等の実装パターン
  def role_text
    case role
    when "staff" then "スタッフ"
    when "manager" then "マネージャー"
    end
  end

  # アクセス可能なデータスコープ
  def accessible_inventories
    store.inventories
  end

  def accessible_store_inventories
    store.store_inventories.includes(:inventory)
  end

  # パスワード有効期限チェック
  def password_expired?
    return true if must_change_password?
    return false if password_changed_at.nil?

    password_changed_at < 90.days.ago
  end

  # アカウントがアクティブかチェック（Devise用）
  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :account_inactive
  end

  # ============================================
  # クラスメソッド
  # ============================================

  # メールアドレスでの検索（大文字小文字を区別しない）
  def self.find_for_authentication(warden_conditions)
    conditions = warden_conditions.dup
    email = conditions.delete(:email)
    store_id = conditions.delete(:store_id)

    where(conditions)
      .where([ "lower(email) = :value", { value: email.downcase } ])
      .where(store_id: store_id)
      .first
  end

  # CSV/一括インポート用
  def self.import_from_csv(file, store)
    # TODO: Phase 3 - CSV一括インポート機能
    # 優先度: 中
    # 実装内容: 店舗スタッフの一括登録
    # 期待効果: 新規店舗開設時の効率化
    raise NotImplementedError, "CSV import will be implemented in Phase 3"
  end

  private

  # ============================================
  # プライベートメソッド
  # ============================================

  def update_password_changed_at
    self.password_changed_at = Time.current
    self.must_change_password = false
  end

  def downcase_email
    self.email = email.downcase if email.present?
  end

  def normalize_name
    self.name = name.strip if name.present?
  end

  def send_welcome_email
    # TODO: Phase 2 - ウェルカムメール送信
    # StoreUserMailer.welcome(self).deliver_later
  end

  def password_not_recently_used
    # TODO: Phase 2 - パスワード履歴チェック
    # 過去5回のパスワードと重複していないかチェック
  end

  # パスワード必須チェック（Devise用）
  def password_required?
    !persisted? || !password.nil? || !password_confirmation.nil?
  end
end

# ============================================
# TODO: Phase 2以降で実装予定の機能
# ============================================
# 1. 🔴 二要素認証（2FA）サポート
#    - TOTP/SMS認証の実装
#    - 管理者は2FA必須化
#
# 2. 🟡 監査ログ機能
#    - 全ての認証イベントの記録
#    - 不審なアクセスパターンの検出
#
# 3. 🟢 シングルサインオン（SSO）
#    - 将来的な統合認証基盤への対応
#    - SAML/OAuth2サポート
