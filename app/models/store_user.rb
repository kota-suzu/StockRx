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

  # ============================================
  # バリデーション
  # ============================================
  validates :name, presence: true, length: { maximum: 100 }
  validates :email, presence: true,
                   format: { with: URI::MailTo::EMAIL_REGEXP },
                   uniqueness: { scope: :store_id, case_sensitive: false,
                               message: "は既にこの店舗で使用されています" }
  validates :role, presence: true, inclusion: { in: %w[staff manager] }
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
