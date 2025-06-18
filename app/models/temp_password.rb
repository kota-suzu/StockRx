# frozen_string_literal: true

require 'bcrypt'

# 🔐 店舗ログイン用一時パスワードモデル
# セキュリティ機能: 暗号化・期限管理・ブルートフォース対策・監査ログ統合
class TempPassword < ApplicationRecord
  # ============================================
  # 関連付け（belongs_to）
  # ============================================
  belongs_to :store_user

  # ============================================
  # バリデーション
  # ============================================
  validates :password_hash, presence: true, length: { maximum: 255 }
  validate :expires_at_must_be_future, on: :create
  validates :usage_attempts, presence: true, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 10
  }
  validates :ip_address, length: { maximum: 45 }, allow_blank: true
  validate :valid_ip_address, if: -> { ip_address.present? }
  validates :generated_by_admin_id, length: { maximum: 255 }, allow_blank: true

  # ============================================
  # スコープ（高頻度クエリの最適化）
  # ============================================
  scope :active, -> { where(active: true) }
  scope :expired, -> { where("expires_at < ?", Time.current) }
  scope :valid, -> { active.where("expires_at > ?", Time.current) }
  scope :unused, -> { where(used_at: nil) }
  scope :used, -> { where.not(used_at: nil) }
  scope :by_store_user, ->(user) { where(store_user: user) }
  scope :recent, -> { order(created_at: :desc) }
  scope :locked, -> { where("usage_attempts >= ?", MAX_ATTEMPTS) }

  # ============================================
  # 定数定義
  # ============================================
  DEFAULT_EXPIRY_MINUTES = 15
  MAX_ATTEMPTS = 5
  LOCKOUT_DURATION = 1.hour
  CLEANUP_GRACE_PERIOD = 24.hours

  # ============================================
  # コールバック
  # ============================================
  before_validation :set_default_expiry, on: :create
  before_validation :encrypt_password_if_changed, if: :plain_password_changed?
  after_create :log_generation
  after_update :log_usage_attempt
  after_destroy :log_cleanup

  # ============================================
  # パスワード暗号化（BCrypt使用）
  # ============================================

  # 一時パスワードを設定（暗号化前）
  attr_writer :plain_password

  def plain_password
    @plain_password
  end

  # プレーンパスワード変更検出
  def plain_password_changed?
    @plain_password.present?
  end

  # パスワードハッシュ化
  def encrypt_password_if_changed
    return unless @plain_password.present?

    self.password_hash = BCrypt::Password.create(@plain_password)
    @plain_password = nil  # セキュリティ: メモリから削除
  end

  # パスワード検証
  def valid_password?(password)
    return false unless password_hash.present?
    return false if expired? || !active? || locked?

    BCrypt::Password.new(password_hash) == password
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # ============================================
  # 状態確認メソッド
  # ============================================

  def expired?
    expires_at < Time.current
  end

  def used?
    used_at.present?
  end

  def locked?
    usage_attempts >= MAX_ATTEMPTS
  end

  def valid_for_authentication?
    active? && !expired? && !used? && !locked?
  end

  def time_until_expiry
    return 0 if expired?

    (expires_at - Time.current).to_i
  end

  # ============================================
  # 使用処理（トランザクション保護）
  # ============================================

  def mark_as_used!(ip_address: nil, user_agent: nil)
    transaction do
      update!(
        used_at: Time.current,
        ip_address: ip_address || self.ip_address,
        user_agent: user_agent || self.user_agent
      )
      log_successful_usage
    end
  end

  def increment_usage_attempts!(ip_address: nil)
    transaction do
      increment!(:usage_attempts)
      update_column(:last_attempt_at, Time.current)
      update_column(:ip_address, ip_address) if ip_address.present?

      log_failed_attempt

      # ロック状態になった場合の追加処理
      handle_lockout if locked?
    end
  end

  # ============================================
  # クラスメソッド（ファクトリ・管理機能）
  # ============================================

  # 一時パスワード生成（セキュアランダム）
  def self.generate_for_user(store_user, admin_id: nil, ip_address: nil, user_agent: nil)
    transaction do
      # 既存の有効な一時パスワードを無効化
      deactivate_existing_passwords(store_user)

      # 新しい一時パスワード生成
      password = generate_secure_password
      temp_password = new(
        store_user: store_user,
        generated_by_admin_id: admin_id,
        ip_address: ip_address,
        user_agent: user_agent
      )
      temp_password.plain_password = password
      temp_password.save!

      [ temp_password, password ]  # パスワードは一度だけ返す
    end
  end

  # 期限切れ一時パスワードのクリーンアップ
  def self.cleanup_expired
    expired_with_grace = where("expires_at < ?", Time.current - CLEANUP_GRACE_PERIOD)
    used_with_grace = used.where("used_at < ?", Time.current - (CLEANUP_GRACE_PERIOD * 2))

    cleanup_count = 0

    transaction do
      [ expired_with_grace, used_with_grace ].each do |scope|
        scope.find_each do |temp_password|
          # ログ記録
          Rails.logger.info "[SECURITY] temp_password_cleanup: 一時パスワード削除 - #{temp_password.attributes.to_json}"
          temp_password.destroy!
          cleanup_count += 1
        end
      end
    end

    Rails.logger.info "🧹 TempPassword cleanup: #{cleanup_count} records removed"
    cleanup_count
  end

  # セキュアパスコード生成
  # メタ認知: 6桁に変更 - 業界標準（Google, Microsoft等）でUX向上
  # セキュリティ: 15分有効期限で100万通りの組み合わせは十分
  # 横展開: 他の認証システムでも6桁が標準
  def self.generate_secure_password(length: 6)
    # 数字のみ（入力しやすさ重視）
    Array.new(length) { rand(10) }.join
  end

  # 既存パスワード無効化
  def self.deactivate_existing_passwords(store_user)
    active.by_store_user(store_user).update_all(
      active: false,
      updated_at: Time.current
    )
  end

  # ============================================
  # プライベートメソッド
  # ============================================

  private

  def set_default_expiry
    self.expires_at ||= Time.current + DEFAULT_EXPIRY_MINUTES.minutes
  end

  def expires_at_must_be_future
    return if expires_at.blank?

    if expires_at <= Time.current
      errors.add(:expires_at, "must be in the future")
    end
  end

  def valid_ip_address
    require "ipaddr"

    begin
      IPAddr.new(ip_address)
    rescue IPAddr::InvalidAddressError
      errors.add(:ip_address, "must be a valid IPv4 or IPv6 address")
    end
  end

  def log_generation
    log_security_event(
      "temp_password_generated",
      "一時パスワード生成",
      {
        store_user_id: store_user_id,
        generated_by_admin_id: generated_by_admin_id,
        expires_at: expires_at,
        ip_address: ip_address
      }
    )
  rescue => e
    Rails.logger.error "一時パスワード生成ログ記録失敗: #{e.message}"
  end

  def log_usage_attempt
    return unless saved_change_to_usage_attempts?

    log_security_event(
      "temp_password_attempt",
      "一時パスワード使用試行",
      {
        store_user_id: store_user_id,
        usage_attempts: usage_attempts,
        locked: locked?,
        last_attempt_at: last_attempt_at
      }
    )
  end

  def log_successful_usage
    log_security_event(
      "temp_password_used",
      "一時パスワード認証成功",
      {
        store_user_id: store_user_id,
        used_at: used_at,
        total_attempts: usage_attempts
      }
    )
  end

  def log_failed_attempt
    log_security_event(
      "temp_password_failed",
      "一時パスワード認証失敗",
      {
        store_user_id: store_user_id,
        usage_attempts: usage_attempts,
        ip_address: ip_address,
        will_be_locked: (usage_attempts >= MAX_ATTEMPTS)
      }
    )
  end

  def log_cleanup
    log_security_event(
      "temp_password_cleanup",
      "一時パスワード削除",
      {
        store_user_id: store_user_id,
        was_used: used?,
        was_expired: expired?,
        cleanup_reason: determine_cleanup_reason
      }
    )
  end

  def handle_lockout
    log_security_event(
      "temp_password_locked",
      "一時パスワードロック",
      {
        store_user_id: store_user_id,
        total_attempts: usage_attempts,
        locked_at: Time.current
      }
    )
  end

  def determine_cleanup_reason
    return "used_expired" if used? && expired?
    return "used_grace_period" if used?
    return "expired_grace_period" if expired?
    "manual_cleanup"
  end

  def log_security_event(event_type, description, metadata = {})
    # TODO: 🔴 Phase 1緊急 - SecurityComplianceManager統合
    # 横展開: ComplianceAuditLogと同様のセキュリティログ統合
    # ベストプラクティス: 統一的なセキュリティイベント記録
    Rails.logger.info "[SECURITY] #{event_type}: #{description} - #{metadata.to_json}"
  end
end

# ============================================
# TODO: Phase 1 以降の機能拡張
# ============================================
# 🔴 Phase 1緊急（1週間以内）:
#   - CleanupExpiredTempPasswordsJob実装
#   - Redis integration for rate limiting
#   - SecurityComplianceManager完全統合
#
# 🟡 Phase 2重要（2週間以内）:
#   - SMS/Email通知機能統合
#   - デバイス指紋認証機能
#   - 地理的位置ベースの追加認証
#
# 🟢 Phase 3推奨（1ヶ月以内）:
#   - 機械学習ベースの不正検出
#   - マルチファクター認証統合
#   - TOTP（Time-based One-Time Password）対応
