# frozen_string_literal: true

# APIキー管理モデル
# CLAUDE.md準拠: API認証のためのキー管理
class ApiKey < ApplicationRecord
  # 関連
  belongs_to :admin, optional: true
  belongs_to :store_user, optional: true
  
  # バリデーション
  validates :key, presence: true, uniqueness: true
  validates :name, presence: true
  validates :expires_at, presence: true
  validate :must_have_owner
  
  # スコープ
  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  
  # コールバック
  before_validation :generate_key, on: :create
  before_validation :set_default_expiry, on: :create
  
  # 暗号化
  encrypts :key, deterministic: true
  
  # APIキーが有効かチェック
  def active?
    !revoked? && !expired?
  end
  
  # APIキーが失効しているかチェック
  def revoked?
    revoked_at.present?
  end
  
  # APIキーが期限切れかチェック
  def expired?
    expires_at <= Time.current
  end
  
  # APIキーを失効させる
  def revoke!(reason: nil)
    update!(
      revoked_at: Time.current,
      revoked_reason: reason
    )
  end
  
  # 最後の使用を記録
  def record_usage!(ip_address: nil, user_agent: nil)
    update_columns(
      last_used_at: Time.current,
      last_used_ip: ip_address,
      last_used_user_agent: user_agent,
      usage_count: usage_count + 1
    )
  end
  
  # 所有者を取得
  def owner
    admin || store_user
  end
  
  # 所有者タイプを取得
  def owner_type
    if admin.present?
      "Admin"
    elsif store_user.present?
      "StoreUser"
    else
      "Unknown"
    end
  end
  
  # レート制限用の識別子
  def rate_limit_identifier
    "api_key:#{id}"
  end
  
  # APIキーをマスク表示（セキュリティ用）
  def masked_key
    return nil if key.blank?
    
    # 最初の8文字と最後の4文字を表示
    if key.length > 12
      "#{key[0..7]}...#{key[-4..]}"
    else
      "#{key[0..3]}..."
    end
  end
  
  # JSON出力時の属性制御
  def as_json(options = {})
    super(options.merge(
      except: [:key], # キーは含めない
      methods: [:masked_key, :active?, :owner_type]
    ))
  end
  
  private
  
  # APIキーを生成
  def generate_key
    self.key ||= SecureRandom.urlsafe_base64(32)
  end
  
  # デフォルトの有効期限を設定（1年後）
  def set_default_expiry
    self.expires_at ||= 1.year.from_now
  end
  
  # 所有者の存在を確認
  def must_have_owner
    if admin.blank? && store_user.blank?
      errors.add(:base, "管理者または店舗ユーザーのいずれかが必要です")
    end
    
    if admin.present? && store_user.present?
      errors.add(:base, "管理者と店舗ユーザーの両方を設定することはできません")
    end
  end
end